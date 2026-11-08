---
"better-supabase": minor
---

`better-supabase/server` is down to the core. Import the account and support helpers from `better-supabase/server/accounts`, the CSV helpers from `better-supabase/server/csv` and the rate-limit header helpers from `better-supabase/server/rate-limit`. The old names have no alias.

| Old import from `better-supabase/server`                                                                                   | New import                          |
| -------------------------------------------------------------------------------------------------------------------------- | ----------------------------------- |
| `deleteAccount`, `endSessions`, `suspendAccount`, `lastSignIns`, `supportSessions`, `supportStorage`, `sessionStatusRoute` | `better-supabase/server/accounts`   |
| `toCsv`, `csvColumns`, `csvResponse`                                                                                       | `better-supabase/server/csv`        |
| `rateLimitHeader`, `rateLimitPolicyHeader`, `isRateLimitPolicyName`, `periodSeconds`                                       | `better-supabase/server/rate-limit` |
