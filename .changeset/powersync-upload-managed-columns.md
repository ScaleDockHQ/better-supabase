---
"better-supabase": patch
---

The PowerSync upload routes replay with `{ override: true }`, so a row written offline keeps the `created_at`, `updated_at`, actor and trash values its device stamped. Before, the timestamps plugin refused them and every offline insert on a table with timestamps was discarded.
