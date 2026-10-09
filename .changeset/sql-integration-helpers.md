---
"better-supabase": minor
---

SQL modules call each other through shared helpers and declare the modules they work with, and fewer modules pull in others they only use when present. Run `better-supabase sql sync`.

- `ModuleContext` gains `record`, `notify`, `enqueue`, `entitlements`, `broadcast`, `can` and `staff`. Each returns a statement or expression that is valid without the other module, so a module installs alone and calls the other one once it is installed.
- `SqlModule.integrates` lists the optional modules a module works with. `ctx.installed` and `ctx.of` throw for a module it neither requires nor lists, `better-supabase sql list` prints "works with", and the blocks overview has the full matrix.
- `inbox` no longer requires `jobs` or `streams`: without `jobs` it queues no bot or delivery jobs. `workflows` no longer requires `jobs`, and `ai-cache` no longer requires `tenant`.
- `webhooks-in` requires `updated-at`, which its trigger uses.
- `support.ended` records the session's tenant in the audit log and the outbox, like `support.started`.
- `sql.modules.jobs.schema` is rejected: the jobs module always installs in `better_supabase`, so a schema only pointed the modules that call it at missing functions. Functions of the `access` module are always called in `better_supabase`, whatever `sql.modules.access.schema` sets for its tables.
