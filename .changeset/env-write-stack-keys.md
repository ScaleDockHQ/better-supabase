---
"better-supabase": minor
---

`better-supabase env` writes the full stack env: `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` under their plain names for server code, the same two with the browser prefix, and the new `SUPABASE_JWKS_URL`. The secret key, database URL and JWT secret never get a browser prefix. `--write <file>` names the file (`--out` still works), and `--prefix` takes a framework name (`next`, `vite`, `expo`, `nuxt`, `astro`, `sveltekit`), `none`, or the prefix itself. Help lists a long alias after the flag it stands for.
