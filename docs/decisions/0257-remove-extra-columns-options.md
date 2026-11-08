# 0257: Remove the extraColumns options and the Create design's extraColumns

- Status: accepted
- Date: 2026-11-07
- Amends: 0256

## Context

ADR 0256 made an app file's columns fields of the block, and kept the 45
`*ExtraColumns` options so the codemod could read them. The codemod ran in the
example app and the options have no other reader, so they are now a second way
to say what the schema files already say.

## Decision

The options are gone from every block's `options.ts`, from the module `names.options`
lists, the block option registry and the JSON Schema. A config that still sets one
fails at render time with a message that names `better-supabase codemod
extra-columns`, and doctor BS378 is removed because nothing can set them.
Fifteen blocks had no other option and no longer have an options schema.

The codemod no longer renders the blocks to find a column's table. It keeps the
table each option named in `src/sql/legacy-options.ts` (the expenses block adds
its columns to `expenses` when it has no reports table), resolves the physical
name through the module context with the legacy keys stripped, and for a table
the app creates it lists the columns in the table comment as `@bsb fields a, b`
(or adds the comment). `appColumnsOf` reads that tag, with the type text from the
app's `create table`, so a table the app owns keeps its columns and the block
still takes the listed ones as fields.

`gen` writes the typed `columns` of `blocks.config.ts` from the same app columns
(`appColumnsFor`), and the flags doctor rule reads `expires_at` from them.

The Create design lost `extraColumns`: the `CreateDesign` type, the design JSON
Schema, `setExtraColumn` and `deleteExtraColumn`, the schema metadata that listed
the tables taking them, the design issues and the catalog's `extraColumns` field.
A design with the key fails as `unknown_key`.

## Alternatives considered

Keeping the options as accepted but ignored keys would let an old config render
without the columns and break at run time. A hard error with the codemod's name
fails earlier and says what to do.

## Consequences

An app column is the only source of a block's extra fields. The `@bsb fields`
line is the opt-in for a table the app creates, so the block does not return
columns it does not know about. The docs pages that described each option now
point to the schema-file form.
