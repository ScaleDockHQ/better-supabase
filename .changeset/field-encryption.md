---
"better-supabase": minor
---

Add the `field-encryption` block and audited reads, for apps that keep values such as a diagnosis or a birth date.

- `field-encryption` keeps one data key per tenant, user or app in Supabase Vault and encrypts values with pgcrypto (AES-256). `drop_field_key(owner)` deletes a key, which shreds every value sealed under it, and records `field_key.dropped`.
- An app table column takes `encrypted: true`. It is stored as ciphertext, hidden from signed-in users, and read through `public.<table>_reveal(ids)`, which returns the configured types for the rows in the caller's scope. `gen` types the column as its configured type. An encrypted column can't be unique, indexed, a reference, an identity, `text[]`, or used where the database reads the value.
- Custom fields take `encryptDefinition(id)` for `text`, `email` and `url` fields, and `listDefinitions` reports `encrypted`. The definitions table gains an `encrypted` column, added to an adopted table too unless you map `blocks.custom-fields.columns.definitions.encrypted` to `null`; run `sql sync` and generate a migration.
- `appTables.<t>.auditReads` and the `custom-fields` option `auditReads` write one audit entry per tenant and call, with the new category `read`, the acting member and the row ids. They need the `audit` block.
- Designs that use `encrypted` or `auditReads` are design format 6, and turning encryption on or off is a breaking change in the design diff.

There is no searchable equality on encrypted values; see the Field encryption docs page for the limits.
