# 1301: Compare statements by their canonical text, and version the content hash

- Status: accepted
- Date: 2026-11-23

## Context

`migrationFile` names a migration `<stamp><suffix>_<hash>.sql`, and an earlier
run's file with the same hash is reused instead of written again. The hash was
the first 8 hex digits of the SHA-256 of the text with `--` lines dropped and
whitespace collapsed. It has no version, so any change to it would silently
rewrite the name of every statement set and re-emit migrations already pushed.
The data-migration sync compared statements by the same whitespace-collapsed
text, so a statement that differed in keyword case or identifier quoting was
written again.

## Decision

Statements compare by the parser's deparse (`canonicalSql` and
`canonicalKey` in `src/cli/schema-reader`). Spacing, comments, keyword case and
redundant quoting do not change it. Quoted names that fold differently, string
contents and every other difference in meaning do. CRLF and LF text give the
same canonical text. A statement that does not parse falls back to its
whitespace-collapsed text.

The content hash is versioned. Version 2 is the first 8 hex digits of the
SHA-256 of the canonical text, written as `_v2-<hash>` before `.sql`. Version 1
is the old hash and has no tag. `CONTENT_HASH_VERSION` in
`migration-names.ts` is 2.

Old hashes upgrade by recognition, not by rename. `migrationFile` computes the
version 2 hash and the version 1 hash of the new contents and treats an
existing migration with either name as the same file, so a pushed migration is
never renamed and a sync after the upgrade writes nothing new. New files get
the version 2 name. Text that does not parse keeps the version 1 name. The
helpers that strip the hash (`hasMigrationSuffix`, `squash`) accept both forms.
`migrationFile` is async because deparse is.

## Alternatives considered

- Rename existing files to version 2. A migration that was pushed or applied
  is never rewritten (repo rule), and the Supabase CLI keys it by stamp.
- Keep the hash and only change the comparison. A change to what the hash
  covers later would still be unversioned.
- Hash the parse tree JSON. It carries byte offsets, so a reformat would
  change the hash.

## Consequences

An existing project sees no new migration from the upgrade. A bump of the
Postgres grammar that changes the deparse of a statement would change version
2 names, so such a change needs `CONTENT_HASH_VERSION` to move to 3 with the
same recognition of version 2.
