# 1226: Borrow from pgsql-parser without taking it as a dependency

- Status: accepted
- Date: 2026-11-23

## Context

[pgsql-parser](https://github.com/constructive-io/pgsql-parser) is a family of
packages around libpg_query: a parser, a deparser written in TypeScript, a
tree walker (`@pgsql/traverse`), node builders and a generator that reads the
Postgres protobuf schema (`pg-proto-parser`). It covers the same ground as
`@supabase/pg-parser`, which the CLI already pins under
[ADR 1171](1171-four-parsers-and-planners-are-direct-dependencies.md), and a
fifth direct dependency needs its own ADR.

Three things in it would help the schema reader. Its statement splitter
tracks parentheses and `BEGIN ATOMIC ... END` blocks, where ours ended a
statement at every top-level semicolon, which split a SQL-standard function
body and a multi-action rule. Its walker visits a tree from a field table,
with a path to each node, and fills in the type of fields that hold a bare
message, such as `CreatePolicyStmt.table`, a `RangeVar` without its tag. Its
tests round-trip the Postgres regression scripts through deparse.

## Decision

We don't depend on any pgsql-parser package. We take the three ideas and
build them on what we already ship.

1. `statementEnds` in `src/cli/schema-reader/statement-ends.ts` ends a
   statement only at a semicolon outside parentheses and outside a
   `BEGIN ATOMIC ... END` block (with `CASE ... END` nested inside it). When
   the nesting never closes, every semicolon ends a statement, as before.
   `statementsOf`, `rawStatementsOf` and `codeStatementsOf` share it.
2. `scripts/gen-pg-node-fields.ts` reads the type declarations
   `@supabase/pg-parser` ships for Postgres 15, 16 and 17 with `oxc-parser`
   (also pinned under ADR 1171) and writes
   `src/cli/schema-reader/node-fields.generated.ts`. `walk.ts` visits a tree
   from that table, with a `NodePath` and visitors typed per node from
   `@supabase/pg-parser/17/types`. `columnRefs` and `blocksWrites` use it.
   `walk.test.ts` fails when the installed package no longer matches the
   table.
3. `scripts/curate-pg-regress.ts` downloads nine regression scripts from
   libpg_query at the tag pg-parser builds Postgres 17 from, checks their
   SHA-256, and keeps the statements that parse alone. `corpus.test.ts` reads
   each file, compares the split count with the parse count, and checks that
   `canonicalSql` parses back to the same tree once positions are dropped.

What only the parser package can add is asked upstream:
[Postgres 18](https://github.com/supabase-community/pg-parser/issues/36),
[PL/pgSQL bodies](https://github.com/supabase-community/pg-parser/issues/37),
[a synchronous API](https://github.com/supabase-community/pg-parser/issues/38),
[split, fingerprint, normalize and summary](https://github.com/supabase-community/pg-parser/issues/39),
[a node field schema and walker](https://github.com/supabase-community/pg-parser/issues/40)
and [deparse options](https://github.com/supabase-community/pg-parser/issues/41).

## Alternatives considered

- Take `pgsql-parser` and `@pgsql/traverse` as dependencies. They bring a
  second libpg_query build next to pg-parser's, a second set of tree types
  that differ in small ways (field casing, enum encoding), and a fifth direct
  dependency for the CLI, for a walker of about a hundred lines.
- Generate the field table with `pg-proto-parser` from `pg_query.proto`. It
  adds a devDependency and reads a schema one step removed from the types the
  walker is checked against. The `.d.ts` files are exactly those types.
- Keep blind recursion over every key. It can't tell a node from a bare
  message, so a visitor for `RangeVar` misses the policy's table, and a
  `SAFETY` cast sits at every step.

## Consequences

The splitter now agrees with the parser on function bodies and rules, and the
regression corpus checks that on about five thousand statements. A pg-parser
bump runs `pnpm --filter better-supabase gen:pg-node-fields` and, when the
Postgres 17 tag changes, the curation script with new hashes. When pg-parser
ships a field schema or walker (issue 40), `walk.ts` moves onto it and the
generator goes. When it ships a synchronous API or a PL/pgSQL parser (issues
38 and 37), groups 1 and 2 of
[ADR 1212](1212-render-path-takes-facts-as-plain-data.md) can leave text.
