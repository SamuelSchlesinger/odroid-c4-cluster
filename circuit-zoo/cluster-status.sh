#!/bin/bash
# Check status of circuit_zoo cluster deployment

echo "=== Circuit Zoo Cluster Status ==="
echo

echo "--- Kubernetes Pods ---"
ssh admin@node1.local "kubectl get pods -l app=circuit-worker -o wide" 2>/dev/null || echo "No K8s pods found"

echo
echo "--- Database Stats ---"
psql -d samuel -c "
SELECT
    n,
    COUNT(*) as functions_found,
    MAX(size) as max_size,
    ROUND(AVG(size)::numeric, 2) as avg_size,
    COUNT(DISTINCT worker_id) as workers
FROM functions
GROUP BY n
ORDER BY n;
" 2>/dev/null || echo "Database query failed"

echo
echo "--- Per-Worker Counts (n=5) ---"
psql -d samuel -c "
SELECT
    worker_id,
    COUNT(*) as found,
    MAX(size) as max_size,
    MAX(discovered_at) as last_discovery
FROM functions
WHERE n = 5
GROUP BY worker_id
ORDER BY worker_id;
" 2>/dev/null || echo "No n=5 data yet"

echo
echo "--- Recent Discoveries ---"
psql -d samuel -c "
SELECT truth_table, size, depth, worker_id, discovered_at
FROM functions
WHERE n = 5
ORDER BY discovered_at DESC
LIMIT 5;
" 2>/dev/null || echo "No recent discoveries"
