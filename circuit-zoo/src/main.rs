use clap::Parser;
use dashmap::DashMap;
use rayon::prelude::*;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;
use tokio_postgres::{Client, NoTls};

type TruthTable = u64;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum GateType {
    #[serde(rename = "and")]
    And,
    #[serde(rename = "or")]
    Or,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum CircuitNode {
    #[serde(rename = "lit")]
    Literal { var: usize, neg: bool },
    #[serde(rename = "and")]
    And { left: TruthTable, right: TruthTable },
    #[serde(rename = "or")]
    Or { left: TruthTable, right: TruthTable },
}

#[derive(Debug, Clone)]
pub struct FunctionInfo {
    pub size: usize,
    pub depth: usize,
    pub circuit: CircuitNode,
}

fn literal_truth_table(var: usize, negated: bool, n: usize) -> TruthTable {
    let rows = 1usize << n;
    let mut tt: TruthTable = 0;
    for row in 0..rows {
        let bit = (row >> var) & 1;
        let value = if negated { 1 - bit } else { bit };
        tt |= (value as TruthTable) << row;
    }
    tt
}

/// Distributed worker that syncs with Postgres
pub struct DistributedWorker {
    n: usize,
    rows: usize,
    num_functions: u64,
    max_size: usize,
    worker_id: String,
    /// Local cache of known functions
    functions: DashMap<TruthTable, FunctionInfo>,
    depths: DashMap<TruthTable, usize>,
    found_count: AtomicU64,
    /// Buffer of new discoveries to write to DB
    pending_writes: Arc<RwLock<Vec<(TruthTable, FunctionInfo)>>>,
    /// Database connection string
    db_url: String,
    /// Sync interval in seconds
    sync_interval: u64,
}

impl DistributedWorker {
    pub fn new(n: usize, max_size: usize, worker_id: String, db_url: String) -> Self {
        let rows = 1usize << n;
        let num_functions = if rows <= 63 { 1u64 << rows } else { u64::MAX };

        let worker = DistributedWorker {
            n,
            rows,
            num_functions,
            max_size,
            worker_id,
            functions: DashMap::new(),
            depths: DashMap::new(),
            found_count: AtomicU64::new(0),
            pending_writes: Arc::new(RwLock::new(Vec::new())),
            db_url,
            sync_interval: 5,
        };

        // Initialize with literals
        for var in 0..n {
            for negated in [false, true] {
                let tt = literal_truth_table(var, negated, n);
                if !worker.functions.contains_key(&tt) {
                    worker.functions.insert(
                        tt,
                        FunctionInfo {
                            size: 0,
                            depth: 0,
                            circuit: CircuitNode::Literal { var, neg: negated },
                        },
                    );
                    worker.depths.insert(tt, 0);
                    worker.found_count.fetch_add(1, Ordering::Relaxed);
                }
            }
        }

        worker
    }

    /// Connect to Postgres
    async fn connect(&self) -> Result<Client, tokio_postgres::Error> {
        let (client, connection) = tokio_postgres::connect(&self.db_url, NoTls).await?;

        // Spawn connection handler
        tokio::spawn(async move {
            if let Err(e) = connection.await {
                eprintln!("Database connection error: {}", e);
            }
        });

        Ok(client)
    }

    /// Load existing functions from database
    async fn load_from_db(&self, client: &Client) -> Result<usize, tokio_postgres::Error> {
        let rows = client
            .query(
                "SELECT truth_table, size, depth, circuit FROM functions WHERE n = $1",
                &[&(self.n as i16)],
            )
            .await?;

        let mut loaded = 0;
        for row in rows {
            let tt: i64 = row.get(0);
            let size: i16 = row.get(1);
            let depth: i16 = row.get(2);
            let circuit: serde_json::Value = row.get(3);

            let tt = tt as TruthTable;
            if !self.functions.contains_key(&tt) {
                let circuit_node: CircuitNode = serde_json::from_value(circuit).unwrap();
                self.functions.insert(
                    tt,
                    FunctionInfo {
                        size: size as usize,
                        depth: depth as usize,
                        circuit: circuit_node,
                    },
                );
                self.depths.insert(tt, depth as usize);
                self.found_count.fetch_add(1, Ordering::Relaxed);
                loaded += 1;
            }
        }

        Ok(loaded)
    }

    /// Write pending discoveries to database
    async fn flush_to_db(&self, client: &Client) -> Result<usize, tokio_postgres::Error> {
        let mut pending = self.pending_writes.write().await;
        if pending.is_empty() {
            return Ok(0);
        }

        let to_write: Vec<_> = pending.drain(..).collect();
        drop(pending);

        let mut written = 0;
        for (tt, info) in &to_write {
            let circuit_json = serde_json::to_value(&info.circuit).unwrap();
            let result = client
                .execute(
                    "SELECT upsert_function($1, $2, $3, $4, $5, $6)",
                    &[
                        &(*tt as i64),
                        &(self.n as i16),
                        &(info.size as i16),
                        &(info.depth as i16),
                        &circuit_json,
                        &self.worker_id,
                    ],
                )
                .await?;
            if result > 0 {
                written += 1;
            }
        }

        Ok(written)
    }

    /// Run the distributed search
    pub async fn run(&self) -> Result<(), Box<dyn std::error::Error>> {
        let client = self.connect().await?;
        let start = Instant::now();

        println!("Worker {} starting for n={}", self.worker_id, self.n);
        println!("Using {} threads", rayon::current_num_threads());
        println!("Database: {}", self.db_url);

        // Load existing data from database
        let loaded = self.load_from_db(&client).await?;
        println!(
            "Loaded {} functions from database, local total: {}",
            loaded,
            self.found_count.load(Ordering::Relaxed)
        );

        // Build available_at_size from loaded functions
        let mut available_at_size: Vec<Vec<TruthTable>> = vec![Vec::new(); self.max_size + 1];
        for entry in self.functions.iter() {
            let size = entry.value().size;
            if size <= self.max_size {
                available_at_size[size].push(*entry.key());
            }
        }

        // Determine starting size (skip already completed sizes)
        let mut start_size = 1;
        for size in 1..=self.max_size {
            if !available_at_size[size].is_empty() {
                start_size = size + 1;
            }
        }
        if start_size > self.max_size {
            start_size = self.max_size;
        }

        println!("Starting search from size {}", start_size);

        // Spawn background sync task
        let pending_clone = self.pending_writes.clone();
        let db_url_clone = self.db_url.clone();
        let worker_id_clone = self.worker_id.clone();
        let n = self.n;
        let sync_interval = self.sync_interval;

        tokio::spawn(async move {
            loop {
                tokio::time::sleep(Duration::from_secs(sync_interval)).await;

                // Connect and sync
                if let Ok((sync_client, connection)) =
                    tokio_postgres::connect(&db_url_clone, NoTls).await
                {
                    tokio::spawn(async move {
                        let _ = connection.await;
                    });

                    let mut pending = pending_clone.write().await;
                    let to_write: Vec<_> = pending.drain(..).collect();
                    drop(pending);

                    for (tt, info) in to_write {
                        let circuit_json = serde_json::to_value(&info.circuit).unwrap();
                        let _ = sync_client
                            .execute(
                                "SELECT upsert_function($1, $2, $3, $4, $5, $6)",
                                &[
                                    &(tt as i64),
                                    &(n as i16),
                                    &(info.size as i16),
                                    &(info.depth as i16),
                                    &circuit_json,
                                    &worker_id_clone,
                                ],
                            )
                            .await;
                    }
                }
            }
        });

        // Main search loop
        for size in start_size..=self.max_size {
            let current_found = self.found_count.load(Ordering::Relaxed);
            if current_found >= self.num_functions {
                println!("All {} functions found!", self.num_functions);
                break;
            }

            let new_this_size = self.search_size_parallel(size, &available_at_size);
            let new_count = new_this_size.len();
            available_at_size[size] = new_this_size;

            let total_found = self.found_count.load(Ordering::Relaxed);
            let pending_count = self.pending_writes.read().await.len();
            let pct = 100.0 * total_found as f64 / self.num_functions as f64;

            println!(
                "Size {:2}: {:8} new, total {:10} ({:6.3}%), pending: {}, {:.2}s",
                size,
                new_count,
                total_found,
                pct,
                pending_count,
                start.elapsed().as_secs_f64()
            );

            // Periodic full sync with database
            if size % 3 == 0 {
                let loaded = self.load_from_db(&client).await?;
                if loaded > 0 {
                    println!("  Synced {} new functions from other workers", loaded);
                }
            }
        }

        // Final flush
        let written = self.flush_to_db(&client).await?;
        println!("Final flush: wrote {} functions to database", written);

        println!(
            "\nSearch complete in {:.2}s",
            start.elapsed().as_secs_f64()
        );
        self.print_statistics();

        Ok(())
    }

    fn search_size_parallel(
        &self,
        size: usize,
        available_at_size: &[Vec<TruthTable>],
    ) -> Vec<TruthTable> {
        let mut work_items: Vec<(usize, usize)> = Vec::new();
        for s1 in 0..size {
            let s2 = size - 1 - s1;
            if s2 <= s1 {
                work_items.push((s1, s2));
            }
        }

        let new_tts: Vec<TruthTable> = work_items
            .par_iter()
            .flat_map(|&(s1, s2)| {
                let list1 = &available_at_size[s1];
                let list2 = &available_at_size[s2];
                let same_size = s1 == s2;

                list1
                    .par_iter()
                    .enumerate()
                    .flat_map(|(i1, &tt1)| {
                        let mut local_new: Vec<TruthTable> = Vec::new();
                        let start_j = if same_size { i1 } else { 0 };

                        for &tt2 in &list2[start_j..] {
                            let and_result = tt1 & tt2;
                            if self.try_insert(and_result, size, tt1, tt2, true) {
                                local_new.push(and_result);
                            }

                            let or_result = tt1 | tt2;
                            if self.try_insert(or_result, size, tt1, tt2, false) {
                                local_new.push(or_result);
                            }
                        }
                        local_new
                    })
                    .collect::<Vec<_>>()
            })
            .collect();

        new_tts
    }

    fn try_insert(
        &self,
        tt: TruthTable,
        size: usize,
        left: TruthTable,
        right: TruthTable,
        is_and: bool,
    ) -> bool {
        if self.functions.contains_key(&tt) {
            return false;
        }

        let depth = 1 + self
            .depths
            .get(&left)
            .map(|d| *d)
            .unwrap_or(0)
            .max(self.depths.get(&right).map(|d| *d).unwrap_or(0));

        let entry = self.functions.entry(tt);
        match entry {
            dashmap::Entry::Occupied(_) => false,
            dashmap::Entry::Vacant(vacant) => {
                let circuit = if is_and {
                    CircuitNode::And { left, right }
                } else {
                    CircuitNode::Or { left, right }
                };

                let info = FunctionInfo {
                    size,
                    depth,
                    circuit,
                };

                vacant.insert(info.clone());
                self.depths.insert(tt, depth);
                self.found_count.fetch_add(1, Ordering::Relaxed);

                // Queue for database write
                if let Ok(mut pending) = self.pending_writes.try_write() {
                    pending.push((tt, info));
                }

                true
            }
        }
    }

    fn print_statistics(&self) {
        println!("\n=== Statistics for n={} ===\n", self.n);

        let mut size_counts: HashMap<usize, usize> = HashMap::new();
        let mut depth_counts: HashMap<usize, usize> = HashMap::new();

        for entry in self.functions.iter() {
            let info = entry.value();
            *size_counts.entry(info.size).or_insert(0) += 1;
            *depth_counts.entry(info.depth).or_insert(0) += 1;
        }

        let found = self.found_count.load(Ordering::Relaxed);

        println!("Size distribution:");
        let mut sizes: Vec<_> = size_counts.keys().collect();
        sizes.sort();
        for &s in &sizes {
            let count = size_counts[&s];
            println!(
                "  Size {:2}: {:8} ({:5.2}%)",
                s,
                count,
                100.0 * count as f64 / found as f64
            );
        }

        let total_size: usize = self.functions.iter().map(|e| e.value().size).sum();
        println!(
            "\nMean size: {:.3}",
            total_size as f64 / found as f64
        );
    }
}

#[derive(Parser, Debug)]
#[command(name = "circuit_zoo")]
#[command(about = "Distributed circuit search worker")]
struct Args {
    /// Number of input variables
    #[arg(short, long, default_value = "4")]
    n: usize,

    /// Maximum circuit size to search
    #[arg(short = 's', long, default_value = "15")]
    max_size: usize,

    /// PostgreSQL connection URL
    #[arg(
        short,
        long,
        default_value = "host=localhost user=samuel dbname=samuel"
    )]
    database: String,

    /// Worker ID (defaults to hostname)
    #[arg(short, long)]
    worker_id: Option<String>,

    /// Number of threads (defaults to all cores)
    #[arg(short, long)]
    threads: Option<usize>,

    /// Run in local-only mode (no database)
    #[arg(long)]
    local: bool,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args = Args::parse();

    // Set thread count
    if let Some(threads) = args.threads {
        rayon::ThreadPoolBuilder::new()
            .num_threads(threads)
            .build_global()
            .unwrap();
    }

    let worker_id = args
        .worker_id
        .unwrap_or_else(|| hostname::get().unwrap().to_string_lossy().to_string());

    if args.local {
        // Run local-only parallel search (original behavior)
        println!("Running in local-only mode");
        let worker = DistributedWorker::new(args.n, args.max_size, worker_id, String::new());

        // Build available_at_size
        let mut available_at_size: Vec<Vec<TruthTable>> = vec![Vec::new(); args.max_size + 1];
        for entry in worker.functions.iter() {
            if entry.value().size == 0 {
                available_at_size[0].push(*entry.key());
            }
        }

        let start = Instant::now();
        for size in 1..=args.max_size {
            let new = worker.search_size_parallel(size, &available_at_size);
            let count = new.len();
            available_at_size[size] = new;
            let total = worker.found_count.load(Ordering::Relaxed);
            let pct = 100.0 * total as f64 / worker.num_functions as f64;
            println!(
                "Size {:2}: {:8} new, total {:10} ({:6.3}%), {:.2}s",
                size,
                count,
                total,
                pct,
                start.elapsed().as_secs_f64()
            );

            if total >= worker.num_functions {
                println!("All functions found!");
                break;
            }
        }
        worker.print_statistics();
    } else {
        // Run distributed mode
        let worker = DistributedWorker::new(args.n, args.max_size, worker_id, args.database);
        worker.run().await?;
    }

    Ok(())
}
