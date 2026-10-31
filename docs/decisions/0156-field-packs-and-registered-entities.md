# 0156: Field definitions name registered subject types, and packs install them

- Status: accepted
- Date: 2026-10-31

## Context

`field_definitions.entity` was free text, so a typo created a second set of
fields that no record type ever read, and a bulk import had no way to ask
which entities exist. Industries also repeat the same fields for the same
record types, and the library must not ship any of them. Organizations with
several legal entities need a value per entity next to the organization's
value.

## Decision

- `entity` is a registered subject type: a key of `config.subjects`, or a type
  an installed block registers (`fieldSubjects`). `save_field_definition`,
  `install_field_pack` and `import_field_value` fail with
  `FIELD_ENTITY_UNKNOWN` for any other value. The check renders only when the
  app registers types, so a project without subjects keeps free text.
  `better_supabase.subject_types()` is the runtime lookup.
- `options.entityMap` maps stored entities to registered types. The 3 to 4
  upgrade renames the definitions and their value rows, and skips a rename
  that would collide on `(tenant, entity, key)`.
- A field pack is `defineFieldPack({ apiVersion: 1, key, version, subjects })`.
  `install_field_pack(tenant, pack jsonb)` upserts definitions by (pack, key)
  and records `pack` and `pack_version`. A key a pack doesn't own fails with
  `FIELD_PACK_CONFLICT`, and a pack never deletes a definition. Packs are a
  versioned extension interface with a conformance kit (`testFieldPack`).
- With the `legal-entities` block the module adds a nullable
  `field_values.legal_entity_id`. Its unique key becomes an index on the
  tenant, subject, definition and `coalesce(legal_entity_id, zero uuid)`.
  Reads return the entity's value, then the organization's.
- `field_value` is an `imports` target: the subject is named by its external
  key through the record map.

## Consequences

- Breaking: apps with free-text entities map them with `entityMap` before the
  upgrade, and the guide and the codemod say so.
- The library holds no industry fields; the docs show a neutral pack.
- The entity list is fixed when the SQL renders, so adding a subject type
  needs a regenerated schema, the same as the other subject checks.
