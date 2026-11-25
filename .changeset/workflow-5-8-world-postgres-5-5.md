---
"better-supabase": minor
---

The Workflow SDK block and `better-supabase/workflow-sdk/world` move to Workflow 5.8 and `@workflow/world-postgres` 5.5, and `better-supabase/eve` to eve 1.5. The World speaks `@workflow/world` 5.4.0, so the peer ranges become `workflow >=5.8.0 <6`, `@workflow/world >=5.4.0 <5.5`, `@workflow/world-postgres >=5.5.0 <5.6` and `eve >=1.5.0 <2`. The `workflow-sdk` SQL module is at version 10: it adds `workflow.workflow_rate_limits` (world-postgres migration 0033), closed to the API roles.

The other peer floors move to the releases the repo tests, among them `ai >=7.0.181 <8`, `@ai-sdk/react >=4.0.186 <5`, `@ai-sdk/workflow >=2.0.113 <3`, `@orpc/server >=2.0.0-beta.53 <3`, `@nestjs/common >=12.6.0 <13`, `astro >=7.4.13 <8`, `hono >=4.13.21 <5`, `nuxt >=4.7.0 <5`, `react-router >=8.5.2 <9`, `@sveltejs/kit >=3.4.0 <4`, `@tanstack/react-start >=1.169.7 <2`, `stripe >=23.2.0 <24`, `redis >=6.4.0 <7` and `undici >=8.13.1 <9`.

Behaviour changes to check:

- Run `better-supabase upgrade` (or apply the `workflow-sdk` version 10 migration) before you deploy world-postgres 5.5.0.
- `assertWorldMigrations`, which the World runs at startup, throws on a `@workflow/world-postgres` older than 5.5.0.
- The World's `capabilities` report `rateLimits: false` and `rateEventsInBatch: false`. It mints spec 8 runs, so world-postgres 5.5's rate limits stay off and the new table stays empty.
- `EveAuthRejection` carries eve 1.5's error lineage, so eve's `HttpError.is` accepts it and `routeAuth` answers with its response. Under eve 1.4 the check matched by name.
- The React hooks write their latest-callback refs in a layout effect instead of during render, which the React Compiler requires. A test that mocks `react` has to provide `useLayoutEffect`.
- `signIn` returns a `redirectTo` that is not a valid URL unchanged, and Supabase Auth rejects it, instead of throwing. An eve connection whose callback URL is not a valid URL fails with `ConnectionAuthorizationFailedError` (`reason: "invalid_callback_url"`) instead of a `TypeError`.
