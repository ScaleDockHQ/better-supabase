---
"better-supabase": minor
---

Custom field definitions now name a registered subject type. `save_field_definition` fails with
`FIELD_ENTITY_UNKNOWN` for an entity that is not a key of `config.subjects` or a type an installed
block registers, and `blocks.custom-fields.options.entityMap` renames the entities you stored
before. Add field packs with `defineFieldPack`, the `packs` option and `install_field_pack`, which
installs definitions idempotently by pack and key. With the `legal-entities` block, `field_values`
gains a nullable `legal_entity_id`, and `readValues` and `setValue` take `{ legalEntity }`. The
`imports` block gets a `field_value` target, and `testFieldPack` checks a pack. Run
`better-supabase upgrade`, map old entities in `entityMap` and apply the new migrations.
