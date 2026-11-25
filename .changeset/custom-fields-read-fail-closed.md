---
"better-supabase": patch
---

`read_field_values` under `readAccess: "record"` no longer returns values of a record type that declares no read permission to any signed-in caller: such a type keeps the `custom_fields.read` tenant key. Run `better-supabase upgrade` to regenerate the custom-fields module.
