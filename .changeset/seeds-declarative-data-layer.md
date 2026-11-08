---
"better-supabase": minor
---

`better-supabase add --adopt` writes only the data statements that no data migration holds yet, and `add --adopt --check` and `upgrade --check` exit with 1 when one is missing. The `membership_roles` backfill moved out of the memberships schema file into its data file. Doctor gains BS357 (a data file insert without a key), BS358 (an app seed that writes a table a block seeds) and BS359 (a `seed_*_defaults` function without a locale).
