---
"better-supabase": patch
---

Search no longer creates its index triggers on the tables of blocks that render after it. Each of those blocks adds the trigger to its own file, so a design that searches a later block's table (the helpdesk preset's tickets, for example) applies on a fresh database.
