---
"better-supabase": minor
---

Drive access runs over an app's own tables and authorization rules.

- `options.roleFunctions.node` and `options.roleFunctions.drive` name schema-qualified functions that return the caller's role on a node or a drive, replacing the block's own grants at that level. `options.readPolicy: false` leaves the read policies to the app.
- Drive grants accept `user` and `team` columns as well as `principalType` and `principalId`, and node grants accept user and team columns too. Managed node and drive grant tables can be created with user and team columns.
- A mapped node drive column stays in use when `options.drives` is off, so an adopted table keeps its drive relationship while the block's drive features stay off.
