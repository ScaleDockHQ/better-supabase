---
"better-supabase": patch
---

`better-supabase/postgres` opens a transaction and sets its claims, role and timeouts in one message, so a statement for a signed-in session costs three round trips instead of four. The values are written as escape string literals, which hold on a server with `standard_conforming_strings` on or off.
