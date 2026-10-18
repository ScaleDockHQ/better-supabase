---
"better-supabase": patch
---

Doctor's BS321 check no longer reads `create extension` inside a string literal as a statement. The jobs module's error message that tells you to create `pg_cron` was reported as an extension no migration creates.
