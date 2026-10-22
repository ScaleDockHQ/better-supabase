# 0087: Encrypt fields with per-owner Vault keys and audit reads where they decrypt

- Status: accepted
- Date: 2026-10-22

## Context

Clinics and other regulated apps keep values such as a diagnosis, a birth
date or a national id in app tables and custom fields. They need those values
unreadable at rest (in backups, replicas, logs and a leaked `select`), a way
to erase one tenant's values, and a record of who read which record when.
Column access (ADR 0051) hides a column from signed-in users but stores it in
plaintext. The audit log (ADR 0034) records writes, not reads. Signing keys
(ADR 0033) already keep private key material in Vault and never in config.

## Decision

The `field-encryption` block gives each owner one random 32-byte data key,
stored as the Vault secret `bs:field-key:<owner>` with the owner
`tenant:<id>`, `user:<id>` or `app`. `field_seal` encrypts a value with
pgcrypto (`pgp_sym_encrypt`, AES-256, one S2K pass since the key is random)
and stores `bsf1:` plus base64; `field_open` passes a value without the
prefix through unchanged, so existing plaintext keeps reading until it is
sealed. The key helpers are revoked from every API role, the service role
too; only definer functions call them. `drop_field_key(owner)` deletes the
key, which shreds every value sealed under it.

An app table column with `encrypted: true` is created as `text` and hidden
from signed-in users with the column grants of ADR 0051. A `before insert or
update` definer trigger (`bs_seal_fields`) checks the column's format,
options and bounds on the plaintext, then seals it with the row's owner key,
and re-seals when the row moves to another owner. `public.<table>_reveal(ids)`
returns the encrypted columns in their configured types for the ids within the
caller's scope, at most 500 per call, and loads one key per owner. It is a
`security invoker` wrapper around the definer function
`better_supabase.<table>_reveal`, so the definer stays out of the schemas
PostgREST exposes, as the library's other definer functions do, and doctor
needs no exception for it. Custom fields gain an `encrypted` definition column,
`encrypt_field_definition(id)` for `text`, `email` and `url` fields, and
encryption inside `set_field_value` and decryption inside `read_field_values`.

Reads are audited where values decrypt. `appTables.<t>.auditReads` and the
`custom-fields` option `auditReads` write one entry per tenant and call with
the category `read`, the type `<type>.viewed` (or `field_value.viewed`), the
acting member and the ids in `metadata`, through the new `ctx.audit`, which
writes to the audit log without an outbox event.

The config refuses an encrypted column wherever the database has to read
the value (keys, indexes, references, identities, `text[]`, the subject
title, URL, search and rank group, rollups, lookups, event includes and
version columns), and the design format becomes 6 when a design uses
`encrypted` or `auditReads`.

## Alternatives considered

- One key per column, or per table. It multiplies Vault rows without a gain:
  the threat is a tenant's data leaking or needing erasure, and one key per
  tenant shreds a tenant in one delete.
- Searchable equality through a keyed hash next to the ciphertext. It leaks
  which rows hold the same value, which for a diagnosis or a birth date is
  much of the secret, so we don't offer it. Apps that need lookups keep a
  separate non-sensitive column.
- Encrypting in TypeScript, as signing does (ADR 0033). Every write path
  (PostgREST, imports, bulk edits, triggers, `sql` in server code) would have
  to call the library, and one that didn't would store plaintext. A trigger
  covers them all.
- A `security_invoker` view that decrypts. The key would have to be readable
  by the caller's role, which defeats the point.
- Auditing every row of a read. A list of 200 rows would write 200 entries;
  one entry per tenant and call with the ids keeps a page to one insert.

## Consequences

Values are ciphertext at rest and shred with their key. The service role and
`postgres` can still decrypt, so encryption doesn't protect against a leaked
service key. The database can't search, sort, filter or index encrypted
values, a data export carries ciphertext, the inline custom fields layout
isn't encrypted, and `reveal` checks the table's own scope rather than
policies an app adds by hand. We would revisit searchable encryption if
Postgres or Vault gain a primitive that doesn't leak equality.
