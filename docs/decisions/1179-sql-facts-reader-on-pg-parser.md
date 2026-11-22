# 1179: One SQL facts reader on pg-parser, proven against the text scanners

- Status: accepted
- Date: 2026-11-22

## Context

The CLI reads SQL with about 5,000 lines of regular expressions: `schema-scan.ts`,
`foreign-keys.ts`, the statement splitter and the declaration model of the
pipeline. They misread `begin atomic` bodies, `E'...'` strings, DDL inside a
`do` block, `create temp table`, `partition of`, the second action of an `alter
table`, overloads, `numeric(10,2)` and a `not null` inside a `check`. The same
patterns also hid two generated files that no parser accepts: a column with
`default array['a', 'b']` and a `check (... is not null)` lost the end of their
definition in `alter table ... add column`. ADR 1171 made `@supabase/pg-parser`
a direct dependency for this reason.

## Decision

`src/cli/schema-reader` parses each file once with pg-parser and returns
`FileFacts`: tables with columns, types as written, constraints, foreign keys
(deferrable and match type), alters, drops, enums, views, indexes, policies,
triggers, functions keyed by signature, comments decoded from any quoting,
grants and markers read from `scan()` tokens. A file that does not parse throws
`SchemaReadFailure` with the file, line and column. The parser is async, so
`readSchemaFacts` reads ahead and `factsOf` answers synchronously for code that
cannot wait.

A scanner is replaced only after a test shows equal results on a corpus: the 190
golden modules, the repository's own schema files and the validation project.
The first families proven equal are tables with drops, column types, `not null`,
columns added by `alter table`, enums and row level security. The one
difference is deliberate: the scanner read `not null` inside `check (role is
null or ...)` as a constraint of `role`.

The two scanner bugs the reader exposed are fixed in place: `splitTopLevel`
now counts brackets, and `addable` removes `not null`, `primary key` and
`unique` only outside parentheses. The `moderation` and `waitlist` goldens
change.

## Consequences

The reader covers the families listed above plus views, policy grants, the
extension schema, updated-at triggers, indexes, foreign keys and the
declaration model, each proven equal on about 515 files with the differences
named in `equivalence-queries.test.ts`. ADR 1180 records where the text
scanners stay.
