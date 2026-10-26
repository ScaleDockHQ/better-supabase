---
"better-supabase": minor
---

Every table and sequence a block creates now revokes its privileges from `PUBLIC` as well as `anon` and `authenticated`, and a block instance schema revokes default privileges for objects created later. Existing databases need no migration: the revokes are no-ops where `PUBLIC` holds no grant.
