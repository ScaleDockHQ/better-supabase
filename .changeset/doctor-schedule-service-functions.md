---
"better-supabase": patch
---

Doctor BS512 now finds the `schedule/v1beta` trigger of a schedule that names a `service` in that
service's `functions`, and matches a function by its route file (`app/api/drain/route.ts` for
`api/drain`), so it no longer warns about a schedule that is wired.
