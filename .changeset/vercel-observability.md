---
"better-supabase": minor
---

Observability on Vercel: query metrics, server errors and workflow run outcomes.

- `better-supabase/otel/vercel` exports `vercelMetrics(metric)`, a plugin that sends the duration
  and the failures of every repository operation to Vercel custom metrics through the `metric`
  function of `@vercel/functions`. It makes at most 16 calls per request (`maxCalls`) and sends one
  `budget_exceeded` count past the cap. It has its own entry so an app does not need
  `@opentelemetry/api`.
- `better-supabase/next/instrumentation` exports `createOnRequestError(betterSupabase)`, a handler
  for Next.js's `onRequestError` that emits a `request.failed` block event with the error name, a
  cut message, the digest, the path without its query string and the route context.
- `registerWorkflowLifecycle` in `better-supabase/workflow-sdk` registers the Workflow SDK's
  lifecycle hooks and writes `workflow_sdk.run_completed` and `workflow_sdk.run_failed` to the
  outbox, with the key `<runId>:<transition>`. The SDK reports only completed and failed runs.
- Docs: a Vercel observability page with the `@workflow/web` mount behind `protectWebHandler` and
  recipes for `@vercel/otel` and eve's `agentRuns()`.

Upgrade: nothing breaks. All three are new exports, and `@vercel/functions`, `next` and `workflow`
keep their tested ranges.
