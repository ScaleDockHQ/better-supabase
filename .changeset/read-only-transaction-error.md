---
"better-supabase": patch
---

Postgres error `25006` (a write in a read-only transaction, such as in a read-only support session) maps to `forbidden` with code `25006`, the message "This connection is read-only, so the write was refused" and a hint, instead of `unexpected` with the raw "cannot execute ... in a read-only transaction" text. The original text is kept in `details`.
