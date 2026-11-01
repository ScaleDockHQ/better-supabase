# Budgets and limits

> Verified against Vercel AI Gateway docs (observability-and-spend/budgets, rate-limits; Vercel CLI v59.13.0+ for --default), 2026-10-11

Sources: <https://vercel.com/docs/ai-gateway/observability-and-spend/budgets>, `/rate-limits`, `/authentication-and-byok/api-keys`.

## Four scopes that stack

Team, project (OIDC from that project's deployments), API key, and user (keys attributed to a member). A request must pass every budget in scope; a key attributed to a member counts toward the key, the user and the team budgets. API-key spend is never attributed to a project. BYOK spend is in no budget. Budgets are soft caps: the check runs at the start of the request, so the crossing request completes.

Resets are in UTC: `daily` midnight, `weekly` Monday midnight, `monthly` the first of the month, `none` never (cumulative). Editing keeps the period's spend; deleting removes the cap at once (a covered resource falls back to its default).

## Set them

```bash
vercel ai-gateway budgets set team --limit 500 --refresh-period monthly
vercel ai-gateway budgets set project my-project --limit 200 --refresh-period monthly
vercel ai-gateway budgets set api-key my-key --limit 50 --refresh-period weekly
vercel ai-gateway budgets set user teammate@example.com --limit 100 --refresh-period monthly
vercel ai-gateway budgets list
vercel ai-gateway api-keys create --name contractor --limit 50 --refresh-period none --expiration 30d
```

The numbers above are examples; ask the user for real limits. Defaults cover every resource without a custom budget, including future ones: `vercel ai-gateway budgets set api-key --default --limit <n> --refresh-period monthly` (also `project` and `user`). Each covered resource gets its own allowance, metering starts when the default takes effect, and defaults do not send spend alerts (set a custom budget for alerts). Remove with `vercel ai-gateway budgets remove <scope> [name] [--default]`.

## When exceeded

HTTP `402`, JSON `error.type` `quota_for_entity_exceeded`, with a message naming the scope (team or project text, or `Quota limit exceeded for "api_key_id_..."`). Raise the budget, wait for the reset, or use a different key; do not retry in a loop.

## Rate limits

Free tier: lower per-model limit, `429` with `{"error":{"type":"rate_limit_exceeded"}}`. Paid tier: none from the gateway; custom limits available on request through support. Limits change, so the docs give no fixed numbers.

## Cost visibility

`GET /v1/credits` for balance and spend, `GET /v1/report` for team spend reports, Logs for per-request cost, billed-to-gateway vs BYOK flag in the request details. Custom reporting with tags and user IDs is a paid add-on (see `/observability-and-spend/custom-reporting`).
