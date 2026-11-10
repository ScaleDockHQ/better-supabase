---
"better-supabase": minor
---

The servers no longer have `deleteAccount`, `suspendAccount`, `endSessions` or `lastSignIns` methods, so a route or proxy that never calls them doesn't bundle their code. Import the functions from the new `better-supabase/server/account` and pass the server first. Run `better-supabase codemod account-calls`.

| Old                               | New                                                                     |
| --------------------------------- | ----------------------------------------------------------------------- |
| `bsb.deleteAccount(id, options)`  | `deleteAccount(bsb, id, options)` from `better-supabase/server/account` |
| `bsb.suspendAccount(id, options)` | `suspendAccount(bsb, id, options)`                                      |
| `bsb.endSessions(id)`             | `endSessions(bsb, id)`                                                  |
| `bsb.lastSignIns(ids)`            | `lastSignIns(bsb, ids)`                                                 |

`createNext` still drops the user's cached reads and session memo after each of them.
