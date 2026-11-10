---
"better-supabase": minor
---

`createPostgres` takes `ssl` (`true` verifies the certificate, or `{ ca, rejectUnauthorized }`), and `better-supabase/postgres` exports `sharedPostgres`, which keeps one pool per process and connection string.
