# pgvector beside LiteLLM, llama-swap and Open WebUI

> Verified against pgvector v0.8.7, LiteLLM v1.105.0 and Open WebUI docs (env-configuration, PGVECTOR_*), 2026-10-11

## LiteLLM `/v1/embeddings`

LiteLLM does not proxy Postgres; it serves the embedding model that produces the vectors. Register the embedder (see `text-embeddings-inference` or `infinity`) and match the column dimension.

```yaml
model_list:
  - model_name: embed-default
    litellm_params:
      model: openai/Qwen/Qwen3-Embedding-0.6B
      api_base: http://tei-embed:80/v1
      api_key: os.environ/TEI_API_KEY
    model_info:
      mode: embedding
```

Embed and insert with curl, jq and psql (no key printed, password from `.pgpass`):

```bash
V=$(curl -fsS $LITELLM/v1/embeddings -H "Authorization: Bearer $LITELLM_API_KEY" -H 'content-type: application/json' \
  -d '{"model":"embed-default","input":["pgvector stores vectors in Postgres."]}' | jq -c '.data[0].embedding')
psql "host=127.0.0.1 dbname=rag user=app" -c "INSERT INTO chunks (doc_id, content, embedding) VALUES (1, 'pgvector stores vectors in Postgres.', '$V')"
```

For bulk loads use `COPY` from a script, not row-by-row inserts.

## llama-swap

Not applicable: pgvector is a database extension, not a model process. If the embedder is swapped by llama-swap, point LiteLLM at that entry.

## Open WebUI

Open WebUI supports pgvector as its vector store. Variables from its env reference: `VECTOR_DB=pgvector`, `PGVECTOR_DB_URL` (defaults to `DATABASE_URL`), `PGVECTOR_INITIALIZE_MAX_VECTOR_LENGTH` (default 1536), `PGVECTOR_CREATE_EXTENSION` (default true; false allows a non-superuser role), `PGVECTOR_INDEX_METHOD` (`ivfflat` or `hnsw`), `PGVECTOR_HNSW_M`, `PGVECTOR_HNSW_EF_CONSTRUCTION`, `PGVECTOR_IVFFLAT_LISTS`, `PGVECTOR_ITERATIVE_SCAN`, `PGVECTOR_USE_HALFVEC`, and pool settings. Mind the initial vector length against your embedding dimension (for a 1024-dim model set it deliberately). Pass the URL through an env file, not a command line. RAG configuration is covered by Open WebUI's own skill; changing the embedding model needs re-indexing.
