# Prometheus and Grafana for LLM serving

> Verified against Prometheus 3.x and Grafana 12.x docs, vLLM v0.31.0, SGLang, llama.cpp, llama-swap and LiteLLM v1.105.0 docs, 2026-10-11

Stack notes only. Install, scrape configs, recording rules, dashboards and troubleshooting live in the product skills.

## How it plugs into the stack

| Target        | Port                      | Path                                  | Auth                                                                                |
| ------------- | ------------------------- | ------------------------------------- | ----------------------------------------------------------------------------------- |
| vLLM          | 8000                      | `/metrics`                            | none                                                                                |
| SGLang        | 30000                     | `/metrics`                            | none (needs `--enable-metrics`)                                                     |
| llama.cpp     | 9931 (8080 before b11521) | `/metrics` (`?model=` in router mode) | Bearer key if `--api-key` is set                                                    |
| llama-swap    | 8080                      | `/metrics`                            | Bearer key if `apiKeys` is set                                                      |
| LiteLLM proxy | 4000                      | `/metrics`                            | key required by default; or a dedicated unauthenticated `--prometheus_metrics_port` |
| DCGM exporter | 9400                      | `/metrics`                            | none, or `--web-config-file`                                                        |
| Prometheus    | 9090                      | UI, `/api/v1/*`                       | none by default                                                                     |
| Grafana       | 3000                      | UI                                    | Grafana users                                                                       |

Stack pitfalls:

- LiteLLM `/metrics` returns 401 since v1.85.0 without a key; scrape with `credentials_file`, never inline credentials.
- Multi-worker LiteLLM needs `PROMETHEUS_MULTIPROC_DIR`, or values jump between scrapes.
- Per-user or per-key gateway labels blow up cardinality; check `prometheus_tsdb_head_series`.
- `histogram_quantile` needs `sum by (le, ...)`; keep `rate()` windows at least 4x the scrape interval.

Depth:

- `prometheus-grafana-llm`: `npx skills add ScaleDockHQ/llm-skills --skill prometheus-grafana-llm`
- `dcgm-exporter`: `npx skills add ScaleDockHQ/llm-skills --skill dcgm-exporter`
