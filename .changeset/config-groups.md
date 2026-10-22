---
"better-supabase": minor
---

Breaking: `better-supabase.config.ts` groups its keys into `database` (`source`, `schemas`, `sql`, `seed`, `expose`, `buckets`, `realtime`, `topics`, `vectorSearch`), `auth` (`organization`, `claims`, `authorization`, `entitlements`), `gen` (`output`, `casing`, the generator `tables` overrides and the other type options), `api` (`openapi`, `specs`) and `tooling` (`doctor`, `env`, `keys`, `skills`, `scaffold`). `preset`, `blocks`, `plugins`, `records`, `tables` and `adapters` stay at the top level.

| 0.14                     | 0.15                       |
| ------------------------ | -------------------------- |
| `subjects`               | `records`                  |
| `appTables`              | `tables`                   |
| `appTables.<name>.scope` | `tables.<name>.owner`      |
| `integrations`           | `adapters`                 |
| `sql.scope`              | `database.sql.owner`       |
| `claims.tenant`          | `auth.organization.claim`  |
| `plugins.tenant.column`  | `auth.organization.column` |
| `blocks.<name>.mode`     | `blocks.<name>.ownership`  |
| `blocks.<name>.scope`    | `blocks.<name>.owner`      |
| `blocks.<name>.entities` | `blocks.<name>.names`      |
| `blocks.<name>.hooks`    | `blocks.<name>.callbacks`  |

`better-supabase codemod 0.15` regroups a config file, its environment blocks and a `better-supabase.config.json`. Loading a config with a 0.14 key fails with a message that names the key's new place. `resolveConfig` returns the same resolved config as before, and `flattenConfig`, `groupConfig` and `blockEntrySource` from `better-supabase/config` convert between the two shapes. `init` and `add` write the grouped keys, and CLI and doctor messages name the grouped paths. Doctor finding targets keep their 0.14 names, so saved baselines still match. Create designs keep `appTables` and `scope` in this release.
