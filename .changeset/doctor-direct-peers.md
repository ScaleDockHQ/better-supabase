---
"better-supabase": patch
---

Doctor BS601 now only warns about a peer outside its range when the project's `package.json` lists
it, so packages that another dependency installs for itself, such as `undici` or `vue`, no longer
raise it.
