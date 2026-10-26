---
"better-supabase": patch
---

The service-caller check in block functions reads the role PostgREST switched to before it reads the JWT claim, so a request can't claim the service role through `request.jwt.claims`. Direct connections that only set claims keep working. Run `better-supabase upgrade` to refresh the modules, then generate a migration (ADR 0104).
