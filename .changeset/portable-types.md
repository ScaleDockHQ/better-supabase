---
"better-supabase": patch
---

Two public types no longer rely on DOM-only globals. The `headers` option of `problem()` takes what the global `Headers` constructor accepts, and the JSON Web Keys in `better-supabase/testing` use the `node:crypto` type, so both resolve in a project whose `lib` leaves out `"DOM"`.
