# 0217: Meter background AI runs with sources, organization rules and quotas

- Status: accepted
- Date: 2026-11-03

## Context

Background AI runs (an inbox suggestion, a nightly summary) call models without a request behind them. `meterTelemetry` recorded their tokens under one `ai:telemetry` source, keyed on the telemetry call id, so a retried job counted twice and the usage history couldn't tell one job from another. Rate limits had one rule per scope, so an organization on a bigger plan shared the limit of every other one. Quotas could only be written with SQL.

## Decision

`meterTelemetry` takes `source` (default `ai:<functionId>`), `idempotencyKey(event)` as the base of each row's key, and `actor` and `metadata` resolvers. Rows keep their suffix (response id, embedding call, rerank), so the steps of one run don't collide.

The `rate-limit` module moves to version 2. `rate_limit_rules` gets a nullable `organization_id` and loses its primary key on `scope`; two partial unique indexes allow one global rule and one rule per organization for a scope. `set_organization_rate_limit` writes them, and `hit_rate_limit`, `check_rate_limit` and `check_rate_limits` take an organization and prefer its rule. `check_request` (the Data API hook) reads global rules only, because it doesn't know the organization. `RateLimit.setRule` and the `organizationId` field of `check` and `checkAll` expose this.

`rateLimitMiddleware` in `better-supabase/ai-sdk` is a `LanguageModelMiddleware` that counts each call in `transformParams` and throws a `DbException` (`rate_limited`, code `AI_RATE_LIMITED`, `retryAfter`) before the model runs. A limiter that fails refuses the call unless `failOpen` is set.

The `usage` module moves to version 8 with `set_usage_quota` and `remove_usage_quota` for the service role, and the client gets `setQuota` and `removeQuota`.

## Alternatives considered

- A separate `rate_limit_organization_rules` table: two tables to read on every hit, and an app-owned rules table would need a second mapping.
- A composite primary key on `(scope, organization_id)`: a null organization can't be part of a primary key, so the global rule would need a placeholder uuid.
- Returning a refusal message from the middleware, as the guardrails middleware does: a rate limit is an error the caller retries, not an answer to show.

## Consequences

`better-supabase upgrade` adds the column and drops the old primary key. The fixture schema, golden files, `api/exports.json` and the CLI help snapshots need regenerating. Revisit the middleware if the AI SDK adds a per-call hook that can refuse without throwing.
