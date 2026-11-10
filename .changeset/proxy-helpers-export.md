---
"better-supabase": patch
---

`better-supabase/next/proxy` exports `toSession`, `permissionsOf` and `postAuthPath`, the helpers a `protect` function uses, so a proxy can leave out the `better-supabase/next` entry.
