---
"better-supabase": minor
---

The app can now check permissions and show any subject's title without writing its own queries.

`better-supabase/blocks/access` calls the new `my_permissions(tenant, keys)` SQL function, which returns the keys the caller holds in a tenant. `access.can(key)`, `access.flags({ edit: key })` and `permissionFlags(set, map)` return `canX` booleans typed by the keys you pass, such as the generated `permissions` constant. In React, `usePermission(key)` and `<Can permission={key}>` from `better-supabase/blocks/access/react` share one call per render, and the Vue, Svelte and Solid bindings export `usePermissions`.

`better-supabase/blocks/subjects` resolves `SubjectRef` lists to a title and a path through the new `subject_titles(refs)` SQL function, which runs as the caller and leaves out rows the caller can't read. `useSubject` and `useSubjects` batch every lookup of one render into one call. The new SubjectLink, SubjectChip and Can recipes show them in the Next.js example.

`gen` now writes a `urls` entry for every subject type with a `url` (block entities, `config.subjects` and app table subjects), and `better-supabase add client` passes the generated `blockConfig` to the browser client when the project has blocks.

To upgrade, run `better-supabase sql sync` and generate a migration. With `blocks.access.mode: "custom"`, write `my_permissions(tenant, keys text[] default null) returns text[]` yourself before you use `<Can>`.
