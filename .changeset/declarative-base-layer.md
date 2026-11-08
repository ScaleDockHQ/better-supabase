---
"better-supabase": minor
---

The declarative base layer release gives every name one spelling and makes the files better-supabase writes declarative. The renames ship without aliases. This is a minor release; below 1.0 a minor version may carry breaking changes. Follow the [0.57 to 0.58 guide](https://bettersupabase.com/docs/migration/0.57-to-0.58); this entry lists what breaks, by area.

Run the codemods in this order, then `gen`, `upgrade` and your SQL workflow's sync:

```bash
better-supabase codemod owned-columns
better-supabase codemod extra-columns
better-supabase codemod config
better-supabase codemod generators
better-supabase codemod naming
better-supabase codemod table-modules
better-supabase gen
better-supabase upgrade
```

**Config.** Keys have one spelling each. A config that keeps an old key is refused with the new name. `codemod naming` rewrites the keys that stay under the same parent. Move the flat `organization` key to `auth.tenant` by hand; the codemod reports it and leaves it. `extraColumns` and its prefixed forms are removed from every block (`codemod extra-columns`), and a `columns` entry for a column the view lacks, or a `tenant` that repeats `sql.tenantColumn`, is an error (`codemod config`).

**Exports and types.** The renames of `api/naming.json` apply (`codemod naming`). `better-supabase/config` no longer exports the generators; import them from `better-supabase/generators/<name>` (`codemod generators`). Generators are plugins at `apiVersion: 2`. Every exported `*Args`, `*Settings` and `*Failure` type has a name from its noun.

**Blocks.** `time-tracking` is `time-entries` and `bulk` is `bulk-actions`, with their imports, config keys, clients and permission keys. The tasks block's default entity is `task`. Engagements are activities. The `rank` block keeps its name.

**Database.** Block tables name their tenant column `tenant_id`, user references `<role>_id`, soft-deleted rows `archived_at` and timestamps `*_at`. Generated policies, triggers and check constraints carry a `bsb_` prefix. Three tables are renamed, and the policy helper functions live in `better_supabase`. `codemod naming` writes the rename migrations for an installed app; no data moves.

**Module files.** The files `upgrade` writes are declarative DDL, with shared helpers in one prelude file and unscoped triggers in one file. Row audit triggers are static statements. Migrations the CLI writes are named by stamp and content hash. `powersync streams` declares the `powersync` publication in `supabase/schemas` when that folder exists.

**Generated client code.** `gen` writes one module per table and one slice per block. The server's schema is in `generated-schema.ts` (`codemod table-modules`). Frameworks are registrations through `defineFramework`.

**CLI.** CLI contract 3 follows the Vercel CLI guidelines: exit code 3 is gone, the result documents are `cli-result-v2` and `cli-commands-v2`, and five flags are renamed with `flag_renamed` as the error. `gen --watch` is `dev`, and `db prune-workflows` is `workflows prune`.

**Removed.** The 0.46 and 0.47 rename shims, the module upgrades for tables 0.47 renamed (upgrades start at 0.53), `$apiResult`, the `triggerSql` overload, the module `version` option and the `openapi` config key.

**Deferred.** The generated file layout, reads through a view named after a block instance, child PowerSync streams and the owned-column default flip are not in this release (ADR 0393). Cloud design URLs that were saved earlier carry the old `integrations` field.

| Old                                                                     | New                                                                |
| ----------------------------------------------------------------------- | ------------------------------------------------------------------ |
| `subjects`, `gen.recordTypes`                                           | `recordTypes`, `gen.records`                                       |
| `gen.output` and the other `output` file keys                           | `gen.file` and the other `file` keys                               |
| `integrations`, `organization` (flat)                                   | `adapters`, `auth.tenant`                                          |
| `better-supabase/blocks/time-tracking`, `blocks["time-tracking"]`       | `better-supabase/blocks/time-entries`, `blocks["time-entries"]`    |
| `better-supabase/blocks/bulk`, `blocks.bulk`                            | `better-supabase/blocks/bulk-actions`, `blocks["bulk-actions"]`    |
| `organization_id` on block tables                                       | `tenant_id`                                                        |
| `owner_user_id` and the other `<role>_user_id` columns                  | `owner_id` and the other `<role>_id` columns                       |
| `deleted_at` on `drive_nodes`, `memories`, `messages`                   | `archived_at`                                                      |
| `locked_until`, `scheduled_for`, `purge_after` and the other timestamps | `lock_expires_at`, `scheduled_at`, `purge_at` and so on            |
| `engagement_*` tables, `Engagement*` types, `ENGAGEMENT_*` hints        | `activity_*`, `Activity*`, `ACTIVITY_*`                            |
| `stream_kv`, `invoice_e_endpoints`, `workflow_step_library`             | `stream_entries`, `e_invoice_endpoints`, `workflow_step_templates` |
| `bsb.uid()`, `bsb.owns()`, `bsb.is_member()`, `bsb.can()`               | the same functions in `better_supabase`                            |
| `work_item` (default entity of tasks)                                   | `task`                                                             |
| `defineSupabase`, `getBetterSupabase` (Svelte)                          | `createSupabase`, `betterSupabase`                                 |
| `BSB_STACK`, `BSB_CLOUD_URL`                                            | `BETTER_SUPABASE_STACK`, `BETTER_SUPABASE_CLOUD_URL`               |
| `db seed --apply`, `doctor --fix`, `dev env --write`                    | `db seed --yes`, `doctor --yes`, `dev env --out`                   |
| `gen --emit`, `gen --out-dir`, `gen --watch`                            | `gen --metadata <doc> --only`, `gen --metadata <doc> --out`, `dev` |
| `--confirm <token>`, exit code 3                                        | `--yes --effects-digest <digest>`, exit code 2                     |
| `better-supabase db prune-workflows`                                    | `better-supabase workflows prune`                                  |
