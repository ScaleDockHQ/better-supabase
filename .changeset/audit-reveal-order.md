---
"better-supabase": patch
---

The `audit.revealed` entry an export writes lists the revealed entry ids in the order they occurred, instead of the order Postgres happened to scan them.
