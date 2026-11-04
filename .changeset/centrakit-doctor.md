---
"better-supabase": minor
---

Doctor reports eight shims the library now covers (BS612 to BS619): proxy cookie re-sync with
`setAll`, an Auth call after `bootstrap`, a hand-made authorization version seed, comment paging
that filters `deletedAt`, an author re-read after a comment list, `withPublicPolicyRoles`, a unique
violation found by code or message, and a hand-built support `AuthState`. The shim registry in
`src/cli/doctor/shims.ts` holds them.

`Bootstrap.endReason` is required. A bootstrap wrapper generated before 0.44 returns no `end_reason`
and the call now fails with an error that tells the app to run `sql upgrade`; regenerate the wrapper
and apply the migration.

`createEmployees` accepts the app's own status values in `create`: `gen` writes
`blocks.employees.values.employees.status` into the generated entry as `options.statuses`.

| Old                                           | New                                   |
| --------------------------------------------- | ------------------------------------- |
| A bootstrap wrapper without `end_reason`      | `sql upgrade` and apply the migration |
| `Bootstrap` built without `endReason` (tests) | `endReason: null` or the reason       |
