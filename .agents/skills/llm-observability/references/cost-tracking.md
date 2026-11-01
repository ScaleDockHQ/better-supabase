# Cost tracking

> Verified against LiteLLM v1.105.0 docs (custom pricing, custom model cost map, cost tracking, Prometheus), 2026-10-11

## What it is and when to choose it

Two different cost questions:

1. **Who spends what** (chargeback, budgets, runaway clients): attribute every request to a key, team, user and model, priced in currency. Do this at the gateway.
2. **What does our own capacity cost per token** (self-hosted vs cloud decisions): divide the hardware and power cost by the tokens actually served. Do this from engine/gateway token counters plus a fixed cost model.

LiteLLM covers the first out of the box once every model has a price. The second is arithmetic you set up once.

## Install

Nothing beyond the gateway: LiteLLM writes spend to `LiteLLM_SpendLogs` (Postgres) and exports `litellm_spend_metric` when the `prometheus` callback is on (see `gateway-logging.md`). Each response also carries an `x-litellm-response-cost` header.

```bash
# cost of a single test request, no secrets printed
curl -fsS -D - -o /dev/null http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_API_KEY" -H 'Content-Type: application/json' \
  -d '{"model":"<model>","messages":[{"role":"user","content":"ping"}],"max_tokens":8}' \
  | grep -i '^x-litellm-response-cost'
```

## Minimal working config

Price every deployment explicitly. Cloud models are priced from LiteLLM's model cost map; self-hosted ones are not.

```yaml
model_list:
  # Self-hosted, treated as free: explicit zeros also bypass ALL budget checks for this model
  - model_name: local-chat
    litellm_params:
      model: openai/<served-model-name>
      api_base: http://node-a:8000/v1
      api_key: os.environ/VLLM_API_KEY
    model_info:
      input_cost_per_token: 0
      output_cost_per_token: 0

  # Self-hosted with an internal rate so budgets and chargeback still work
  - model_name: local-chat-metered
    litellm_params:
      model: openai/<served-model-name>
      api_base: http://node-b:8000/v1
      api_key: os.environ/VLLM_API_KEY
    model_info:
      input_cost_per_token: 0.0000001 # your internal rate; see "cost per token" below
      output_cost_per_token: 0.0000004

  # Time-billed backend (dedicated endpoint): v1.105.0+
  - model_name: dedicated-endpoint
    litellm_params:
      model: openai/<model>
      api_base: https://llm.example.com/v1
      api_key: os.environ/DEDICATED_API_KEY
    model_info:
      cost_per_second: 0.0004
```

Numbers are placeholders. Pricing keys can also be set directly in `litellm_params`. Overriding any pricing key detaches that deployment from the default cost map entry, so give the complete rate card (input, output, long-context tiers, cache keys) or requests in the missing tier are under-billed.

## How it plugs into the stack

**Where the numbers live**

| Source                                                                                                              | Use for                                    |
| ------------------------------------------------------------------------------------------------------------------- | ------------------------------------------ |
| `litellm_spend_metric` (Prometheus counter, labels incl. `team_alias`, `api_key_alias`, `model`, `requested_model`) | Dashboards and spend-rate alerts           |
| `LiteLLM_SpendLogs` via `GET /spend/logs/v2` (paginated)                                                            | Per-request audit, exports, reconciliation |
| `/global/spend/report?group_by=team` (Enterprise)                                                                   | Grouped reports                            |
| Budget gauges (`litellm_remaining_team_budget_metric`, `litellm_remaining_api_key_budget_metric`, …)                | "Budget almost exhausted" alerts           |
| `litellm_zero_cost_requests_total{reason=...}`                                                                      | Detect models silently priced at $0        |

**Queries**

```promql
# spend per team, last 24h
sum by (team_alias) (increase(litellm_spend_metric_total[24h]))
# spend rate per model, $/hour
sum by (model) (rate(litellm_spend_metric_total[1h])) * 3600
# requests priced at $0 that should not be
sum by (requested_model, reason) (increase(litellm_zero_cost_requests_total[1h]))
```

**Cost per token for self-hosted capacity**

Monthly cost of a node ÷ tokens it actually served that month:

```
cost_per_1M_output_tokens = (hardware_amortization + power + hosting + ops time) per month
                            / (output tokens served per month / 1e6)
```

Get served tokens from Prometheus rather than from benchmarks, since real utilization is what you pay for:

```promql
# output tokens served per vLLM instance over 30 days
sum by (instance) (increase(vllm:generation_tokens_total[30d]))
# same through the gateway, per model
sum by (model) (increase(litellm_output_tokens_metric_total[30d]))
```

Compare idle capacity too: a GPU serving at low utilization is expensive per token even if its peak throughput is high. Feed the resulting rate back into `input_cost_per_token` / `output_cost_per_token` for chargeback.

## Operating

- Review spend weekly per team and per model; investigate jumps against request volume and output tokens (a prompt change that doubles output length doubles cost).
- Reconcile gateway spend with cloud provider invoices monthly; drift usually means a missing or stale price.
- Verify which pricing map is loaded if you use a custom map: `GET /model/cost_map/source` reports `source` (`remote`/`local`) and `fallback_reason`; a failed fetch silently falls back to the bundled map.
- Keep spend-log retention (`maximum_spend_logs_retention_period`) aligned with finance needs; aggregate older data in Prometheus or a warehouse instead of keeping every row.

## Tuning knobs worth knowing

- `model_info.input_cost_per_token` / `output_cost_per_token`: per-deployment pricing; explicit `0` on both marks a zero-cost model.
- `cost_per_second` (v1.105.0+; older versions use `input_cost_per_second`): time-based pricing.
- `base_model` in `model_info`: maps a custom deployment name to a known model for pricing (useful for Azure-style deployment names).
- `LITELLM_MODEL_COST_MAP_URL`: serve your own full cost map; `LITELLM_LOCAL_MODEL_COST_MAP=True` uses the bundled map offline.
- `enable_end_user_cost_tracking_prometheus_only: true`: per-end-user spend on Prometheus (cardinality and PII trade-off).

## Known pitfalls

- **Zero-cost models bypass every budget** (user, team, organization, global). If budgets must cap a self-hosted model, give it a small non-zero internal rate.
- **Unpriced self-hosted models** (`null` cost) are still budget-checked but have no rate to bill from, so their spend is not meaningful; set explicit prices. `litellm_zero_cost_requests_total` only flags models whose pricing entry has a non-zero rate yet priced a request at $0 (missing key, pricing not applied, calculation error).
- **Partial overrides** detach from default pricing, under-billing long-context or cached requests.
- **Reasoning tokens** are output tokens and can dominate cost; track `litellm_output_reasoning_tokens_metric` where providers report it.
- **Cost per token from benchmarks** overstates efficiency; use served tokens.

## Official links

- LiteLLM custom pricing: https://docs.litellm.ai/docs/proxy/custom_pricing
- LiteLLM custom model cost map: https://docs.litellm.ai/docs/proxy/custom_model_cost_map
- LiteLLM spend tracking: https://docs.litellm.ai/docs/proxy/cost_tracking
- LiteLLM Prometheus (spend and budget metrics): https://docs.litellm.ai/docs/proxy/prometheus
- LiteLLM model cost map (JSON): https://github.com/BerriAI/litellm/blob/main/model_prices_and_context_window.json
