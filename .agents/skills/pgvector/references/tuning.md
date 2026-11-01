# pgvector tuning

> Verified against pgvector v0.8.7 (README Filtering, Iterative Index Scans, Performance, Troubleshooting), 2026-10-11

- **Check the plan.** `EXPLAIN (ANALYZE, BUFFERS) SELECT ... ORDER BY embedding <=> $1 LIMIT 5;` must show an index scan. The query needs `ORDER BY <distance operator> LIMIT n`, a matching operator class and a constant-able query vector.
- **Recall vs speed.** `hnsw.ef_search` (default 40) or `ivfflat.probes` (default 1). Measure recall against exact search (turn the index off in a session with `SET enable_indexscan = off;`).
- **Filtering with approximate indexes.** Filters apply after the index scan, so queries can return fewer rows than `LIMIT`. Since 0.8.0 enable iterative scans: `SET hnsw.iterative_scan = strict_order;` (exact order) or `relaxed_order` (better recall, slightly out of order); `SET ivfflat.iterative_scan = relaxed_order;`. Limits: `hnsw.max_scan_tuples` (default 20,000), `hnsw.scan_mem_multiplier` (default 1), `ivfflat.max_probes`.
- **Selective filters.** For a filter matching few rows, a B-tree on the filter column or partitioning may be better than the vector index; for few distinct values consider partial indexes (`WHERE category_id = 123`); for multitenancy see the README's partitioning guidance.
- **Normalized vectors** (most embedding APIs): inner product `<#>` is the fastest correct choice; cosine and inner product rank identically on unit vectors.
- **Exact search speed.** Raise `max_parallel_workers_per_gather`.
- **Build speed.** Raise `maintenance_work_mem` and `max_parallel_maintenance_workers`; load before indexing.
- **Vacuum.** HNSW vacuum is slow; `REINDEX INDEX CONCURRENTLY name;` then `VACUUM table;`.
- **Monitoring.** `pg_stat_statements`, `EXPLAIN`, index size via `pg_relation_size`. Index build progress: `select phase, round(100.0 * blocks_done / nullif(blocks_total, 0), 1) from pg_stat_progress_create_index;`.
