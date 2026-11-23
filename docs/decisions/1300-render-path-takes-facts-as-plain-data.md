# 1300: The render path takes SQL facts as plain data, and the scanners leave `./sql`

- Status: accepted
- Date: 2026-11-23

## Context

ADR 1179 reads SQL with pg-parser. ADR 1185 kept the regex scanners for the
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
- Wait for a synchronous parser (the second condition of ADR 1185). No such
  parser is on the horizon.

## Consequences

This ADR amends ADR 1185: its "when they can go" condition 1 is the plan
here, and the splitter is gone from `./sql`. The remaining scanners stay
internal until each consumer takes facts. A doctor or test that reads
statements must prime them first (`primeStatements`); an unprimed text throws
instead of falling back to a second reader.
