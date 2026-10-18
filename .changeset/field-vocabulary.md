---
"better-supabase": minor
---

Custom fields gain six types: `email`, `url`, `multi_option`, `user`, `rating` and `currency`. `CUSTOM_FIELD_TYPES` and `CustomFieldType` are exported from `better-supabase/blocks/custom-fields`, and `saveDefinition` takes a `CustomFieldType`. A form field that names a custom field reads the matching forms type: `multi_option` becomes `multi`, `rating` becomes `integer` from 1 to 5, `currency` becomes `integer` (minor units) and `user` becomes `text`.

App table formats and custom field types now come from one list. `FIELD_FORMATS` from `better-supabase/config` gives each format its column types, its check and the input a form renders, and `scaffold screens` reads the input from it.

Migration: run `better-supabase sql sync` and generate a migration. The custom-fields module replaces the inline `field_definitions_type_check` constraint with a named `bs_field_definitions_type` check that lists the new types.
