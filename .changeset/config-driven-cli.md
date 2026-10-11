---
"better-supabase": minor
---

The CLI reads its options from `better-supabase.config.ts`, so `better-supabase gen` is the one command a project runs.

- `gen` runs every generator the config sets up, in order: the typed client, `sql sync`, `spec emit`, the seed client, `scaffold api` and, when listed, `env`. `gen.tasks` or `--tasks` picks the list, `gen --check` checks them all, and `gen --watch` reruns the steps whose inputs changed. `gen.watchInterval` sets the watch interval.
- New config keys give each repeated flag a default: `env.output` and `env.prefix`, `doctor.only`, `doctor.format` and `doctor.output`, `specs.manifest`, `scaffold.api`, `skills.agents` and `keys.output`. A flag still wins for one run.
- `$env.<name>` and the `$development`, `$production`, `$test` and `$ci` blocks override the config per environment. The CLI applies the one named by the new global `--env` flag, then `$BETTER_SUPABASE_ENV`, then `ci` when `$CI` is set. `better-supabase config` shows the active environment.
- `init` records the integrations it set up under `integrations`, and `add` without an argument sets up the listed ones whose files are missing. `scaffold api` and `add` print the config entry for the flags you passed.
