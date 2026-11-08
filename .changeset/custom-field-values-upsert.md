---
"better-supabase": minor
---

The custom-fields block sets, changes and removes a value by itself. `setValue` replaces a value that exists instead of failing on the key of record and field, and an encrypted value is sealed once. New `updateValue({ id, value })` and `deleteValue(id)` call the SQL functions `update_field_value(value_id, value)` and `delete_field_value(value_id)`, which the normalized and inline layouts now have (the keyed layout had them). They replace the app SQL that updated or deleted `field_values` rows. Run `better-supabase upgrade` and generate a migration with `supabase db schema declarative sync`.
