---
"better-supabase": minor
---

A cleanup of shared code inside the package, with a few fixes.

- Fix `doctor` BS303 comparing generated files with a different line-ending rule than `gen`, fix `sql upgrade` ignoring the provider defaults for modules, and flush pending events in `finally` in the React Router, SvelteKit, Hono, Edge and oRPC adapters when a handler throws.
- Bound the HS256 key cache and the verified-token secret ids, and strip the event type prefix the same way in every block.
- Move the Standard Webhooks code to `core/signatures` and the HMAC helpers to `core/hmac`, share one optional-peer loader and one bounded TTL cache, and add `methodNotAllowed()` to `core/problem`. None of these paths are public exports.
- Split `config/config.ts` into `config/types/*`, `expose.ts`, `json.ts`, `resolve.ts` and `defaults.ts`. `resolveConfig` now resolves `gen.watchInterval` (default 2000), the SQL registry and the CLI read their fallbacks from `CONFIG_DEFAULTS`, and `GenTask`, `IntegrationName` and `SkillsAgent` derive from the new `GEN_TASKS`, `INTEGRATION_NAMES` and `SKILLS_AGENTS` tuples, which `better-supabase/config` now exports.
- Split `sql/registry.ts` into `module-types.ts`, `registry.ts`, `module-context.ts`, `render.ts`, `paths.ts`, `markers.ts`, `upgrade.ts`, `introspect.ts` and one file per inline module under `sql/modules`. A module declares `extras` for SQL that depends on the whole layout, replacing the name switch in the renderer, and the tenant and provider entitlement checks share one template.
- Share one cron route guard (`core/cron-route`), one time budget (`budget`), one lease heartbeat, one `blockEmitter` and one `toBlockError` across the jobs, outbox, webhooks, notifications, organizations and billing blocks.
- Split the jobs, billing, notifications, data-lifecycle and webhooks blocks into type, helper and per-factory files; the public subpaths are unchanged.
