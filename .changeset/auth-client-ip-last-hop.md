---
"better-supabase": patch
---

`clientIp(request)` reads the last `x-forwarded-for` hop, the one your own edge appended, instead of the first. A client controls the hops to the left, so it could send any IP as `Sb-Forwarded-For` to Auth on a refresh and dodge Auth's per-IP limit or spend another IP's. Behind more than one proxy, pass your own `clientIp` reader.
