---
"better-supabase": minor
---

`deleteAccount` deletes the Auth user before it removes the user's Storage objects, so a delete the database refuses (an organization's only owner under `ownerInvariant`, say) no longer removes the avatar first. The objects are listed before and removed after. With the new `sql` option (`postgres.admin`, which `server.deleteAccount` passes when the server has `postgres`), a delete that Auth reports only as a generic failure is replayed in a statement that is rolled back, and the database's own error comes back with its SQLSTATE and hint, such as `ORGANIZATION_OWNER_REQUIRED`.
