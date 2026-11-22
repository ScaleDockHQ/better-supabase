# 1180: The text scanners stay on the synchronous render path

- Status: accepted
- Date: 2026-11-22

## Context

ADR 1179 reads SQL with pg-parser and proves its facts equal to the regex
scanners. pg-parser is WebAssembly with an async-only `parse`, `scan` and
`deparse`. It is a CLI dependency (ADR 1171) and no runtime entry may import
it, since runtime entries import no Node built-ins and run on every WinterTC
runtime (invariant 6).

The render pipeline in `src/sql` is a synchronous text to text transform over
generated SQL with marker placeholders. `renderBlocks`, `over-app-tables`,
`index-skip` and the duplicate-object checks scan text they have just produced.
`better-supabase/sql` also exports the scanners (`declaredTables`,
`declaredColumnTypes`, `policyGrants`, `parseDeclared` and the rest), which
apps and the block catalog call without a parser.

## Decision

Everything the CLI reads from files on disk goes through the facts reader. The
loaders (`readSchemaTexts`, `readDeclarativeTexts`), the doctor run, the
project codemods and `powersyncOutput` read their files with the parser first,
and the scans in `src/cli/sql-facts.ts` answer from `factsOf`. A doctor run
keeps empty facts for a file that does not parse, so the other checks still
run. `gen` and the other commands throw `SchemaReadFailure` with the file, line
and column.

The text scanners in `src/sql` stay for the synchronous render path. They are
not deleted and the public `./sql` entry does not change: no export is
removed, so `api/exports.json` stays as it is.

## When they can go

The scanners can be deleted when either condition holds:

1. The render pipeline becomes asynchronous or takes facts as an input, for
   example by rendering the module first and parsing the result once, and the
   `./sql` entry drops the scanners in a major version with a changeset and a
   migration note for callers.
2. A parser that runs synchronously on every runtime, with a size the bundle
   baseline accepts, replaces the WASM one.

Until then a test keeps the two readers equal over the corpus, so a change to a
scanner that moves the result fails the equivalence test first.

## Consequences

There are two readers. The CLI reads from facts and the render path reads
text. Fixing a scanner bug needs the equivalence test to show whether the
reader agrees or the difference is deliberate.
