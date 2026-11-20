---
"better-supabase": minor
---

The Workflow SDK block and `better-supabase/workflow-sdk/world` move to Workflow 5.7 and eve 1.2. The World speaks `@workflow/world` 5.3.0, so the peer ranges become `workflow >=5.7.0 <6`, `@workflow/world >=5.3.0 <5.4`, `@workflow/world-postgres >=5.4.0 <5.5` and `eve >=1.2.0 <2`. The `workflow-sdk` SQL module is at version 6: it adds `workflow.workflow_run_delivery_leases` and `workflow_runs.wake_pending` (world-postgres migrations 0031 and 0032). `better-supabase/workflow-sdk/world/package.json` is a stub manifest that carries the `@workflow/world` range, so eve's startup check compares the Workflow line it bundles with the World's.

Behaviour changes to check:

- Run `better-supabase upgrade` (or apply the `workflow-sdk` version 6 migration) before you deploy Workflow 5.7. Runs that exist before the upgrade start with `wake_pending` set, so startup recovery lets their next completed delivery decide.
- `assertWorldMigrations` throws on a `@workflow/world-postgres` older than 5.4.0.
- eve 1.0 release candidates and releases before 1.2.0 are no longer supported.
