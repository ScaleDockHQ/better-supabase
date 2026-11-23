# 1300: The render path takes SQL facts as plain data, and the scanners leave `./sql`

- Status: accepted
- Date: 2026-11-23

## Context

ADR 1179 reads SQL with pg-parser. [ADR 1185](1185-text-scanners-stay-on-the-render-path.md) kept the regex scanners for the
synchronous render path, because pg-parser is async WebAssembly and runtime
entries import no Node built-ins (invariant 6). That left two readers, and the
public `better-supabase/sql` entry exported six text readers next to the
render functions: `splitStatements`, the scans of `schema-scan.ts` and
`foreign-keys.ts`, and the comment strippers of the pipeline model.

The CLI is already async and reads every file it touches before it renders.
The render functions only need what those files declare, not the text.

## Decision

One reader answers every question about SQL: the facts reader on pg-parser in
`src/cli/schema-reader`. Runtime entries never import it. The design has three
parts.

1. The CLI reads facts with the async reader and hands them to the render
   functions as plain data (`DatabaseFacts`-like input: tables, columns,
   indexes, foreign keys, views, policies, per file). Plain data has no parser
   in it, so it crosses into runtime code without a Node built-in or a WASM
   import, and invariant 6 holds.
2. Code that scans the SQL a render has just produced (`over-app-tables`,
   `index-skip`, the duplicate-object check) stops scanning. The renderer
   already knows what it emitted, so it returns those facts next to the text.
3. The scanners that remain after step 1 and 2 are internal modules, not
   exports of `./sql`. The six text readers are deleted once nothing calls
   them.

The statement splitter is the first reader to go. `statementsOf` in
`src/cli/schema-reader/statements.ts` splits from the parser's scan tokens,
needs no valid grammar (a file that does not parse still splits) and keeps
the lines and comment handling of the old splitter. The CLI primes it with
`primeStatements`, which `primeSchemaFacts` calls for every file it reads.
`splitStatements` and `SqlStatement` are no longer exported from
`better-supabase/sql`; `SqlStatement` lives in the CLI reader.

## Alternatives considered

- Make the render path async. Every block's `render` and each `sql` entry
  would return a promise, and apps that call `renderBlocks` would change for no
  gain: the answer depends on files the caller has already read.
- Import pg-parser lazily from runtime entries. It breaks invariant 6 on
  every WinterTC runtime that has no WebAssembly instantiation by URL.
- Wait for a synchronous parser (the second condition of [ADR 1185](1185-text-scanners-stay-on-the-render-path.md)). No such
  parser is on the horizon.

## Implemented

- The six text readers are deleted from `./sql`: the statement splitter, the
  scans of `schema-scan.ts` and `foreign-keys.ts`, the pipeline model and
  `parse-store.ts`. The exports are listed in the 0.82 to 0.83 migration page.
- Tags, policies, audit registrations and statements come from facts
  (`mappingTagsOf`, `withMappingTags`, `declaredPolicies`,
  `auditRegistrations`, `statementsOf`). The facts carry the declaration model
  and spans, so the four codemods edit by token position.
- Doctor rules that stripped comments use the reader's `withoutComments`. Block
  comments keep their newlines, so line numbers stay true.
- Whitespace compares in `sync` and `diff` use `canonicalSql` (ADR 1301). The
  persisted `rows/read.ts` hash is unchanged.
- The adoption check imports the sql entry, never an internal file, so the CLI
  chunk does not inline the block modules.
- An unprimed text throws. The public role reads as `"public"`.

## Scanners that stay

Four groups of text scanning remain, internal and not exported from `./sql`.

1. Render-path rewriters (`staticDdl`, `rerunnableDdl`, `overAppTables`,
   `indexSkipOf`, `withoutCoveredPolicies`, `withoutAppTablePolicies`,
   `blockNamesOnAppTables` and the synchronous `withoutComments` in
   `text-edit.ts`). They rewrite the text a block has just produced, inside
   the synchronous render. Invariant 6 forbids the parser there, and returning
   facts next to every rendered text would change each block's `render`
   contract for no gain.
2. Readers of plpgsql bodies and catalog expressions (`rls.ts`, `realtime.ts`,
   `trigger-fills.ts`, `model-functions.ts`, `plpgsql-text-writes.ts`,
   `written-values.ts`). pg-parser 0.1.7 returns a function body as a string
   constant and has no plpgsql parser, so the body can only be read as text.
3. Doctor leniency. A file that does not parse keeps empty facts so the other
   checks still run, where `gen` fails with `SchemaReadFailure`. The scanner
   fails a whole text on an unterminated quote, so this is a policy and not a
   second reader.
4. The adopted-columns allowance. The adoption check walks the block registry
   and render pipeline to read what each block writes, and runs only in the
   CLI. First it imported the internals by path under an `ADOPTION` allowance
   in `tests/cli/imports.test.ts`, which inlined every block module into the
   CLI chunk (3.5 MB gzip against 951 KB). It now imports through the entry
   and the allowance is deleted. It still reads block output as text, which
   falls under group 1.

Groups 1 and 2 end when a synchronous parser or a plpgsql parser exists.

## Consequences

This ADR amends [ADR 1185](1185-text-scanners-stay-on-the-render-path.md): its "when they can go" condition 1 is the plan
here, and the splitter is gone from `./sql`. The remaining scanners stay
internal until each consumer takes facts. A doctor or test that reads
statements must prime them first (`primeStatements`); an unprimed text throws
instead of falling back to a second reader.
