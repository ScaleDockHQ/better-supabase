# pgvector schema and indexes

> Verified against pgvector v0.8.7 (README Getting Started, Indexing, HNSW, IVFFlat, halfvec, binary quantization), 2026-10-11

```sql
CREATE EXTENSION IF NOT EXISTS vector;
CREATE TABLE chunks (
  id bigserial PRIMARY KEY,
  doc_id bigint NOT NULL,
  content text NOT NULL,
  embedding vector(1024) NOT NULL      -- dimension must match the embedding model
);
```

Operators: `<->` L2, `<#>` negative inner product, `<=>` cosine, `<+>` L1; bit: `<~>` Hamming, `<%>` Jaccard. Use the operator class that matches your query operator or the index is not used.

Query:

```sql
SELECT id, content FROM chunks ORDER BY embedding <=> $1 LIMIT 5;
```

Without an index, search is exact with perfect recall. Add an approximate index only when needed; results then differ.

## HNSW (default choice)

```sql
CREATE INDEX CONCURRENTLY ON chunks USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64);
```

- `m` default 16, `ef_construction` default 64. Higher values give better recall for more build time and memory.
- No training step; can be created on an empty table. Better speed-recall than IVFFlat, slower to build, more memory.
- Query option `hnsw.ef_search` default 40 (`SET LOCAL hnsw.ef_search = 100;` inside a transaction).
- Use `halfvec_cosine_ops`, `sparsevec_...`, `bit_hamming_ops` for other types.

## IVFFlat

```sql
CREATE INDEX ON chunks USING ivfflat (embedding vector_cosine_ops) WITH (lists = 1000);
```

- Create after loading data. Start with `lists = rows/1000` up to 1M rows, `sqrt(rows)` above.
- `ivfflat.probes` default 1; start at `sqrt(lists)`.
- Faster build and less memory than HNSW, lower recall at the same speed.

## Smaller indexes

```sql
-- half-precision storage
ALTER TABLE chunks ADD COLUMN embedding_h halfvec(1024);
-- half-precision index over full-precision column
CREATE INDEX ON chunks USING hnsw ((embedding::halfvec(1024)) halfvec_cosine_ops);
-- binary quantization with re-ranking
CREATE INDEX ON chunks USING hnsw ((binary_quantize(embedding)::bit(1024)) bit_hamming_ops);
SELECT * FROM (
  SELECT * FROM chunks ORDER BY binary_quantize(embedding)::bit(1024) <~> binary_quantize($1) LIMIT 20
) ORDER BY embedding <=> $1 LIMIT 5;
```

Queries must use the same expression as the index (`embedding::halfvec(1024)` and so on) to hit it. Binary quantization suits high-dimensional, centered embeddings; check recall.

## Hybrid search

pgvector combines with Postgres full-text search (README Hybrid Search section, for example reciprocal rank fusion). Combine in SQL; keep the weights measured on your data.

## Bulk loading

`COPY ... FROM STDIN WITH (FORMAT BINARY)` for speed; add indexes after the initial load; `CREATE INDEX CONCURRENTLY` in production.
