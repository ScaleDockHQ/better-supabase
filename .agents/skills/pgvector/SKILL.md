---
name: pgvector
description: Add vector search to PostgreSQL with pgvector, run beside a self-hosted LLM stack for RAG. Use for CREATE EXTENSION vector, pgvector/pgvector Docker images, vector/halfvec/bit/sparsevec columns, HNSW vs IVFFlat indexes, hnsw.ef_search, iterative scans, maintenance_work_mem, index build time, memory sizing, embeddings via LiteLLM or TEI. Not for Qdrant (qdrant), Milvus (milvus), Chroma (chroma) or MCP exposure (mcp-servers).
license: MIT
compatibility: Linux, macOS or Windows with Docker or a PostgreSQL 13+ server where extensions can be installed, bash, curl, jq and psql. Installing, creating extensions, building large indexes, dropping data or opening ports needs the user's explicit approval.
metadata:
  author: ScaleDockHQ
  version: "0.1.0"
---

# pgvector

Store embeddings in Postgres next to your relational data, index them (HNSW or IVFFlat), size memory, secure the database, and feed it embeddings made through LiteLLM.

**Scope:** the pgvector extension and the Docker image that carries it. General Postgres administration is out of scope. Embedding servers are `text-embeddings-inference` and `infinity`.

Work through the steps in order. Load a reference only when a step names it.

## Discover first

Read-only. Never print connection strings with passwords.

```bash
command -v docker psql && docker ps --format '{{.Names}}\t{{.Image}}\t{{.Ports}}' | grep -i -E 'postgres|pgvector' || true
export PGPASSFILE=${PGPASSFILE:-$HOME/.pgpass}   # 0600 file, never inline passwords
psql "host=127.0.0.1 port=5432 dbname=postgres user=postgres" -Atc "select version()" 2>&1 | head -1
psql "host=127.0.0.1 dbname=postgres user=postgres" -Atc "select name,default_version,installed_version from pg_available_extensions where name='vector'" 2>/dev/null
psql "host=127.0.0.1 dbname=postgres user=postgres" -Atc "show shared_buffers; show maintenance_work_mem; show max_parallel_maintenance_workers" 2>/dev/null
ss -ltnp 2>/dev/null | grep ':5432\b' || true
```

## Decision flow

1. Postgres already in the stack and vectors under a few million: pgvector. One database, transactions, joins, existing backups.
2. Tens of millions with strict latency, rich vector features or heavy quantization: look at `qdrant` or `milvus`.
3. Existing Postgres version known: use the matching `pgvector/pgvector:pg<N>-<distro>` image (`references/install.md`); managed Postgres usually ships the extension already.
4. Pick the index (`references/indexing.md`): exact search for small tables, HNSW by default, IVFFlat for fast builds and low memory.
5. Dimensions over 2,000: `halfvec` (up to 4,000 for indexes) or reduce dimensions.
6. Size memory first (`references/sizing.md`).

## Rules

- **Ask before changing the system.** Containers, `CREATE EXTENSION`, index builds on big tables, `DROP`, and volume removal need approval; take a dump first.
- **Secrets never touch output.** Passwords live in `.pgpass` (`0600`) or an env file read by the container; do not echo `DATABASE_URL`.
- **Bind to loopback or a private network.** Publish `127.0.0.1:5432:5432`; use SCRAM auth and a dedicated role per application.
- **The vector dimension is part of the schema.** Changing the embedding model means a new column or table and re-embedding.
- **Create ANN indexes after bulk loading, use `CREATE INDEX CONCURRENTLY` in production.**
- **Upgrade the extension explicitly** with `ALTER EXTENSION vector UPDATE;` after replacing binaries.
- **Verify upstream.** Limits and defaults come from the pgvector README read on the writing date.

## Workflows

- [ ] Run Postgres with pgvector -> `references/install.md`, `templates/docker-compose.yml`
- [ ] Size memory and disk -> `references/sizing.md`
- [ ] Create schema, load, index, query -> `references/indexing.md`, `templates/schema.sql`
- [ ] Tune queries and recall -> `references/tuning.md`
- [ ] Secure -> `references/security.md`
- [ ] Feed embeddings from LiteLLM, Open WebUI -> `references/combos/llm-stack.md`
- [ ] Upgrade, back up, tear down -> `references/updating.md`
- [ ] Debug -> `references/troubleshooting.md`
- [ ] Verify: `\dx vector` shows the version, `EXPLAIN` shows the index used, recall on a sample matches exact search, and the index size fits the memory plan.

## Reference index

- `references/install.md`: Docker image tags, data directory, other install paths.
- `references/sizing.md`: bytes per vector, index size, memory plan.
- `references/indexing.md`: types, operators, HNSW and IVFFlat options, halfvec, binary quantization.
- `references/tuning.md`: ef_search, probes, iterative scans, filtering, build speed.
- `references/security.md`: roles, auth, TLS, network.
- `references/updating.md`: extension update, Postgres major upgrade, backup, teardown.
- `references/troubleshooting.md`: symptom to fix.
- `references/combos/llm-stack.md`: LiteLLM embeddings, llama-swap, Open WebUI.

## Companion skills

- `text-embeddings-inference`, `infinity`: embedding servers. Install: `npx skills add ScaleDockHQ/llm-skills --skill text-embeddings-inference`.
- `litellm`: embeddings gateway. Install: `npx skills add ScaleDockHQ/llm-skills --skill litellm`.
- `qdrant`: dedicated vector DB. Install: `npx skills add ScaleDockHQ/llm-skills --skill qdrant`.
- `mcp-servers`: expose pgvector to MCP tools. Install: `npx skills add ScaleDockHQ/llm-skills --skill mcp-servers`.
