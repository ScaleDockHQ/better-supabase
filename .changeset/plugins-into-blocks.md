---
"better-supabase": minor
---

The built-in plugins become block extensions, and the `plugins` config key and the six `better-supabase/plugins/*` subpaths go. The `updated-at`, `created-by`, `trash` and `memberships` blocks carry `updatedAtExtension`, `createdByExtension`, `trashExtension` and `membershipsExtension`, and `gen` installs the extensions of the installed blocks in the generated schema, with `validation()` and the generated validators when a schema generator is configured. `auth.organization.column` turns the memberships extension on for an app's own tenancy. The query rules move to `better-supabase/lint` as `guards()`, `safeGuards()`, `recommendedGuards()` and `strictGuards()`, and `validation()` is exported from `better-supabase`. `definePlugin` stays the versioned interface for your own plugins.

`.use()` of an extension the schema already installed replaces it, so passing options still works. A query on an organization table without an organization is now left to RLS by default; set `auth.organization.onMissing: "error"` to fail it. Without Temporal and a `now` option, the updated-at extension leaves `created_at` and `updated_at` to the column defaults and the block's trigger.

Run `better-supabase codemod 0.15` to move the config and the imports. A config that still has `plugins` fails with a message that names the blocks.
