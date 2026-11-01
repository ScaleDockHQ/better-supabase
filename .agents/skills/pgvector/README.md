# pgvector

Add vector search to Postgres with pgvector beside a self-hosted LLM stack: Docker images and the Postgres 18 data path, bytes-per-vector sizing, HNSW and IVFFlat indexes, iterative scans, security, upgrades, and the LiteLLM embedding and Open WebUI wiring.

## Install

```bash
npx skills add ScaleDockHQ/llm-skills --skill pgvector
```

## Rules

- **Ask before changing the system.**
- **Passwords stay in `.pgpass` and `0600` env files.**
- **The vector dimension is schema.**
- **Index after loading; concurrently in production.**

## References

- [`install.md`](references/install.md), [`sizing.md`](references/sizing.md), [`indexing.md`](references/indexing.md), [`tuning.md`](references/tuning.md), [`security.md`](references/security.md), [`updating.md`](references/updating.md), [`troubleshooting.md`](references/troubleshooting.md), [`combos/llm-stack.md`](references/combos/llm-stack.md).

## Companion skills

- `text-embeddings-inference`, `infinity`, `litellm`, `qdrant`, `mcp-servers`.

## License

MIT
