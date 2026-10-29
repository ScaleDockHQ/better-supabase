---
"better-supabase": minor
---

Encrypted app table columns can be searched by an exact value, and the `bsn`, `iban` and `phone_e164` formats check identifiers as they are written. Run `better-supabase upgrade` and generate a migration.

- Lookups: `lookup: true` on an encrypted column (or the `@bsb lookup <column>` tag) adds a `<column>_lookup bytea` column with an index. The seal trigger fills it with an HMAC-SHA256 of the value, trimmed of spaces and lowercased, under a per-owner lookup key kept in Vault next to the data key. `public.<table>_find(column, value)` returns the ids of the rows the caller reaches whose value matches, and `better_supabase.field_lookup(owner, value)` gives the service role the hash to compare itself.
- Crypto-shredding: `drop_field_key(owner)` deletes the owner's lookup key with the data key, so no lookup finds the shredded values.
- Formats: `bsn` (9 digits that pass the elfproef), `iban` (ISO 13616, mod 97) and `phone_e164` join the format registry for app table columns and custom fields. App tables check them in the column check or the seal trigger; `set_field_value` raises `FIELD_VALUE_INVALID` for a custom field value that fails. The SQL functions `bsb_valid_bsn(text)` and `bsb_valid_iban(text)` are created where they are used.
- `SPEC_PINS.iso13616` pins the ISO 13616-1 edition the IBAN check follows.
