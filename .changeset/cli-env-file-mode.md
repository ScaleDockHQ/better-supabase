---
"better-supabase": patch
---

`better-supabase env` writes `.env.local` (or the `--out` file) with mode `0600`, and tightens an existing file's mode even when its contents didn't change. The file holds the secret key, the database URL and the JWT secret, and it used to be created readable by every user on the machine.
