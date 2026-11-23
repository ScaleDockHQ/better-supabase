---
"better-supabase": minor
---

`blocks.drive.options.grants: "roles"` keeps no `drive_grants` table: `roleFunctions.node` alone
names each member's role, `drive_grants(node)` lists the members it gives a role, and
`drive_share` and `drive_unshare` refuse with `DRIVE_SHARING_EXTERNAL`. Authorization providers
can add `functions.roleOn` (`{user}`, `{resource}`, `{id}`), which `roleFunctions.node: { rows }`
calls when the provider's roles are not permission keys, and the provider conformance kit checks
it. The default `grants: "table"` renders the same SQL as before (ADR 1220).
