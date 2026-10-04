---
"better-supabase": minor
---

SQL kit modules now fit existing schemas. `kits.<module>` in the config sets a module's mode (`managed`, `adopt` over your own tables, or `custom` where you write the contract functions), its schema, table and column names, tenant id type and permission keys. Each file's header records the module version and mode, and schema files record them in `better_supabase.kit_modules`. Doctor BS307 checks the functions of custom-mode modules, and BS304 points hand edits at `kits` instead.

The new `access` module gives policies and kit modules one permission check, `can(scope, id, permission)`, with `tenant_ids_with()`, `is_platform()`, `can_user()`, `can_assign()` and `permission_claims()`. `kits.access.model` picks a role list from the config, role and permission tables with per-tenant overrides, PermDock or your own functions, and `kits.access.disabled` switches off tenants and users with a `disabled_at` column. The `tenant` module (version 2) takes its role names from `kits.access.roles`, adds `memberships.last_used_at` and `org_member_role()`, writes the memberships claim as an array or a map (`options.claimFormat`), and reads the active tenant from `kits.access.activeTenant`: a resolver (the default), the claim or a profile column.

For resolvers, `createServer` takes `tenant: (request, auth) => id`, and `context()` takes `{ tenant }`. The tenant becomes `context.tenant`, the `better_supabase.tenant` setting over Postgres and the `x-bs-tenant` header (`TENANT_HEADER`) over the Data API. `postgres.asUser`, `executorFor` and `transaction` take `settings` and `readOnly`. Doctor BS308, with `--as <user id>`, warns when the access token hook writes no tenant claim while the claim is the active tenant.

`better-supabase/config` exports the kit config types (`KitsConfig`, `KitModuleConfig`, `KitMode`, `AccessKitConfig` and `ActiveTenantSource`) for apps that build their `kits` config in a separate module.
