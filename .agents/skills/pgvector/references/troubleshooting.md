# pgvector troubleshooting

> Verified against pgvector v0.8.7 (README Troubleshooting and FAQ), 2026-10-11

| Symptom                                                 | Cause                                                                             | Fix                                                                    |
| ------------------------------------------------------- | --------------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| `extension "vector" is not available`                   | Not installed on the server                                                       | Use the pgvector image or install the package for your Postgres major  |
| `permission denied to create extension`                 | Role is not superuser                                                             | Create as admin; or `PGVECTOR_CREATE_EXTENSION=false` in apps          |
| Query ignores the index                                 | Operator, operator class or expression mismatch; no `LIMIT`; planner chose a scan | `EXPLAIN`; match `vector_cosine_ops` with `<=>`; `ORDER BY ... LIMIT`  |
| Fewer rows than `LIMIT` with a filter                   | Post-filtering on an ANN index                                                    | Enable iterative scans, raise `hnsw.ef_search`, or use partial indexes |
| Fewer results after adding HNSW or IVFFlat              | Approximate search                                                                | Raise `ef_search` or `probes`; recall tradeoff                         |
| `column cannot have more than 2000 dimensions for hnsw` | Index limit for `vector`                                                          | Use `halfvec` (4,000) or reduce dimensions                             |
| Slow HNSW build, NOTICE graph no longer fits            | `maintenance_work_mem` too small                                                  | Raise it for the session; add parallel workers                         |
| Index build fails with shared memory error              | Docker `/dev/shm` 64 MB                                                           | `--shm-size=1g`                                                        |
| Dimension mismatch on insert                            | Embedding model changed                                                           | New column or table, re-embed                                          |
| Data lost after container removal                       | Wrong volume path                                                                 | PG17 and older `/var/lib/postgresql/data`, PG18 `/var/lib/postgresql`  |
| Out of memory                                           | Large index plus many connections                                                 | Lower `work_mem`, pool connections, smaller `m`, `halfvec`             |
| Slow exact search                                       | Sequential scan                                                                   | Parallel workers, or add an index                                      |
| `ALTER EXTENSION vector UPDATE` does nothing            | Binary not replaced                                                               | Install new files first, restart                                       |

```bash
docker logs --tail 100 pgvector
psql "host=127.0.0.1 dbname=rag user=app" -c "EXPLAIN (ANALYZE, BUFFERS) SELECT id FROM chunks ORDER BY embedding <=> (SELECT embedding FROM chunks LIMIT 1) LIMIT 5"
```
