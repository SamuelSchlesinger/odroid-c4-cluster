-- Circuit Zoo Database Schema
-- Central store for distributed circuit search

-- Create database if running manually:
-- CREATE DATABASE circuit_zoo;

-- Functions table: stores optimal circuits for each truth table
CREATE TABLE IF NOT EXISTS functions (
    -- Truth table as primary key (supports up to n=6)
    truth_table BIGINT PRIMARY KEY,
    -- Number of input variables
    n SMALLINT NOT NULL,
    -- Circuit size (number of AND/OR gates)
    size SMALLINT NOT NULL,
    -- Circuit depth (longest path)
    depth SMALLINT NOT NULL,
    -- Circuit structure as JSON
    circuit JSONB NOT NULL,
    -- Timestamp when discovered
    discovered_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    -- Which worker discovered it
    worker_id TEXT
);

-- Index for efficient queries
CREATE INDEX IF NOT EXISTS idx_functions_n ON functions(n);
CREATE INDEX IF NOT EXISTS idx_functions_size ON functions(size);
CREATE INDEX IF NOT EXISTS idx_functions_n_size ON functions(n, size);

-- Search progress table: tracks which size levels have been searched
CREATE TABLE IF NOT EXISTS search_progress (
    n SMALLINT NOT NULL,
    size SMALLINT NOT NULL,
    worker_id TEXT NOT NULL,
    started_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    completed_at TIMESTAMP WITH TIME ZONE,
    functions_found BIGINT DEFAULT 0,
    PRIMARY KEY (n, size, worker_id)
);

-- View: count of functions by n and size
CREATE OR REPLACE VIEW function_counts AS
SELECT n, size, COUNT(*) as count
FROM functions
GROUP BY n, size
ORDER BY n, size;

-- View: search statistics
CREATE OR REPLACE VIEW search_stats AS
SELECT
    n,
    COUNT(*) as total_found,
    MAX(size) as max_size,
    AVG(size)::numeric(5,2) as avg_size,
    AVG(depth)::numeric(5,2) as avg_depth
FROM functions
GROUP BY n;

-- Function to get next unprocessed combinations for a worker
-- This enables work stealing / load balancing
CREATE OR REPLACE FUNCTION claim_work_batch(
    p_n SMALLINT,
    p_size SMALLINT,
    p_worker_id TEXT,
    p_batch_size INT DEFAULT 10000
) RETURNS TABLE(tt1 BIGINT, tt2 BIGINT) AS $$
BEGIN
    -- Return pairs of truth tables that haven't been combined yet
    -- This is a simplified version; real implementation would track processed pairs
    RETURN QUERY
    SELECT f1.truth_table, f2.truth_table
    FROM functions f1
    CROSS JOIN functions f2
    WHERE f1.n = p_n AND f2.n = p_n
    AND f1.truth_table <= f2.truth_table
    ORDER BY RANDOM()
    LIMIT p_batch_size;
END;
$$ LANGUAGE plpgsql;

-- Upsert function for atomic inserts (only insert if size is better)
CREATE OR REPLACE FUNCTION upsert_function(
    p_truth_table BIGINT,
    p_n SMALLINT,
    p_size SMALLINT,
    p_depth SMALLINT,
    p_circuit JSONB,
    p_worker_id TEXT
) RETURNS BOOLEAN AS $$
DECLARE
    inserted BOOLEAN := FALSE;
BEGIN
    INSERT INTO functions (truth_table, n, size, depth, circuit, worker_id)
    VALUES (p_truth_table, p_n, p_size, p_depth, p_circuit, p_worker_id)
    ON CONFLICT (truth_table) DO UPDATE
    SET size = EXCLUDED.size,
        depth = EXCLUDED.depth,
        circuit = EXCLUDED.circuit,
        worker_id = EXCLUDED.worker_id,
        discovered_at = NOW()
    WHERE functions.size > EXCLUDED.size;

    GET DIAGNOSTICS inserted = ROW_COUNT;
    RETURN inserted > 0;
END;
$$ LANGUAGE plpgsql;
