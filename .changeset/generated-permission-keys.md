---
"better-supabase": minor
---

`gen` can write the permission catalog from the block manifests. `entities.<key>.permissions` is now validated: a key is `<block>.<entity>.<verb>` (verbs `read`, `create`, `update`, `archive`, `delete`, `export`, `import`, `manage` plus named domain verbs), and a two-part key a module already checks stays valid. `gen.permissionCatalog: true` (catalog model) writes a `_better_supabase_permission_catalog.sql` migration with a row for every key the installed blocks check or declare and the default grants of the `owner`, `admin` and `member` roles, so a new block's pages no longer answer 403 until a hand-written migration runs. It also writes `permission-scopes.ts` with `apiKeyScopes` and `oauthScopes`. `entities.<key>.recordAccess: "team"` declares record-team access. The advisories, commissions, deadlines, leave, periods and referrals manifests declare their keys.

| Before                                                          | After                                                               |
| --------------------------------------------------------------- | ------------------------------------------------------------------- |
| A catalog migration written by hand for each new block (EX-807) | `gen: { permissionCatalog: true }`, then `gen` writes the migration |
| `entities.<key>.permissions` is free-form and nothing reads it  | Validated as `<block>.<entity>.<verb>`; `gen` reads it              |
| API key and OAuth scope lists edited by hand                    | `apiKeyScopes` and `oauthScopes` from `permission-scopes.ts`        |
| No manifest field for record-team access                        | `entities.<key>.recordAccess: "team"`                               |
