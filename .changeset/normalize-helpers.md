---
"better-supabase": minor
---

`better-supabase/normalize` repairs imported text and shapes names, phones, postal codes, streets, IBANs, BICs and national ids. Locale rules are data, and the named repair packs are `utf8-as-latin1`, `windows-1252`, `cp437` and `cp850`.

`better_supabase.validate_iban` and `better_supabase.normalize_phone` are the SQL forms. `better-supabase upgrade` rewrites the prelude, and the next schema migration adds the two functions. No data migration is needed.
