# Sizing pgvector

> Verified against pgvector v0.8.7 (README Reference, Scaling, Performance, FAQ), 2026-10-11

Storage per value (README):

| Type         | Bytes              |
| ------------ | ------------------ |
| `vector(d)`  | `4 × d + 8`        |
| `halfvec(d)` | `2 × d + 8`        |
| `bit(d)`     | `d / 8 + 8`        |
| `sparsevec`  | `8 × nonzero + 16` |

Index limits: `vector` up to 2,000 dimensions, `halfvec` up to 4,000, `bit` up to 64,000, `sparsevec` up to 1,000 non-zero elements.

```
table_bytes ≈ rows × (bytes per vector + row overhead + other columns)   (TOAST applies to large values)
```

| Rows | Dim  | `vector` | `halfvec` |
| ---- | ---- | -------- | --------- |
| 1M   | 768  | 3.1 GB   | 1.5 GB    |
| 1M   | 1024 | 4.1 GB   | 2.1 GB    |
| 1M   | 3072 | 12.3 GB  | 6.2 GB    |

These numbers are raw vector bytes; add page overhead and your other columns.

## Index memory

The README does not give an HNSW size formula. Measure it: build on a sample (say 100k rows) and read `select pg_size_pretty(pg_relation_size('index_name'))`, then scale linearly. Expect an HNSW index to be of the same order as the vectors it indexes, plus graph links (`m` default 16). IVFFlat indexes are smaller than HNSW.

Indexes do not have to fit in memory, but performance is better if they do (README FAQ). For a smaller working set the README recommends `halfvec` storage, half-precision indexing (`(embedding::halfvec(d))` expression index) and binary quantization with re-ranking.

## Memory plan

- `shared_buffers`: README suggests 25% of server memory as a starting point (use PgTune).
- `maintenance_work_mem`: HNSW builds are much faster when the graph fits; a NOTICE says when it no longer fits. Set per session before `CREATE INDEX`, for example `SET maintenance_work_mem='8GB'`.
- `max_parallel_maintenance_workers` speeds builds (README suggests raising it with the work memory).
- Leave RAM for the OS page cache; the rest of the LLM stack shares the box.
