# 1220: The remaining doctor text rules read tokens

- Status: accepted
- Date: 2026-11-23

## Context

[ADR 1211](1211-doctor-source-rules-read-the-syntax-tree.md) moved the TypeScript doctor rules to the tree and left the rules whose
input is SQL or dotenv on regular expressions. A comment or a quoted string
that named a function, a trigger or a `:6543` URL still produced a finding.
Four codemods also edited the config and its imports by hand.

## Decision

SQL rules read a flat token stream, `codeStatementsOf` in
`src/cli/schema-reader/code-tokens.ts`. It is built from the pg-parser scan
tokens that `primeStatements` already reads: comments are dropped, a string is
one token, and a dollar-quoted body is expanded in place one level deeper, so a
rule can see the statements inside a function body as code. `hooks`,
`dispatch-regression`, `error-codes` and `import-guard` use it. Their codes,
messages and lines stay the same.

Dotenv rules read `readDotenv` (`src/cli/doctor/dotenv.ts`): `#` comments and
`export` are skipped, and a quoted value may run over several lines. `env`
BS501, BS502, BS503, BS506 and BS509, `vercel-env`, and the BS221 and BS226
URL scans use it. BS226 reads TypeScript sources through `stringSites` in
`tree.ts`, which yields string and template pieces with their line, never a
comment. The BS389 purge check reads SQL parts that are not comments and
sources through `mentionsName`.

The codemods go through the shared helpers. `codemod-table-modules` adds its
table imports with `addNamedImports`, which now places a first import after a
leading directive. `codemod-same-tenant` and `codemod-table-tags` remove
config entries with `followImports`, so an entry under a value the config
imports leaves the file that declares it, and `cut.review` reports what could
not be edited. Two cuts in one followed file go to review, because each cut
reads the file from disk.

## Rules that stay on text

- `plain-secrets` and the plpgsql source checks in `hooks`
  (the marker files and the grant source). They read a function body that
  pg-parser returns as one string; there is no plpgsql parser (ADR 1212,
  group 2).
- The render-path rewriters (ADR 1212, group 1): invariant 6 forbids the
  parser in the synchronous render.
- `codemod-server-imports` and `codemod-same-tenant` already parse with
  oxc-parser; they had no text import handling to move.

## The BS725 `alter publication` entry

No baseline entry lives in this repository; it is the one an app adds for
`blocks.notifications.options.realtime: "changes"`. It stays. The module adds
the table to `supabase_realtime` only if the publication exists and does not
list the table yet, inside a `do` block with `execute format`. A plain
`alter publication ... add table` fails when the table is already a member,
and when the publication is absent, so the file could not be loaded twice.
pg-delta cannot read membership from text, so BS725 keeps reporting it. The
migration page says to accept it with a reason.

## Consequences

A rule added later reads the stream or the tree. A text that is not primed
throws; `primeDoctorFacts` primes the code statements of every SQL file.
