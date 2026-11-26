# 1261: Validate composed reads from the query

- Status: accepted
- Date: 2026-11-26

## Context

`ReadSetResult` already names the value a read set returns. The queries are
TypeScript values, so generating a named type per page would copy a type the
compiler already infers. `readSet.parse` only checks the shape: a list is an
array, a count is a number, a gated entry may be null. A page that sends that
value to a client had no per-column check unless someone wrote a second schema
by hand.

## Decision

`better-supabase/result-schema` builds a Standard Schema from the read.
`resultSchema(readSet)` matches `ReadSetResult` of that set.
`specResultSchema(meta, spec)` matches one `QuerySpec`. Both read the selection
from `builderFor(meta).selection` and map columns with `columnKind`, the same
mapping `gen` uses for table validators. Includes become nested schemas, and
`unknownKeys: "reject"` fails a key the read did not select. The default drops
those keys, as `tableSchema` does. Record bindings stay `unknown` until
`registerRpcReturn` names a schema. `readSet.parse` stays structural.

`gen` stops guessing an unknown column type as `string`. The type stays
`unknown`, and one notice lists the columns. Composite types become nested
objects, domains resolve to their base type, and `geometry` and `geography`
become `json`.

## Alternatives considered

Generating a named page type per read set. That pays off when the query is
text, as it is for GraphQL documents and SQL files. A read set is already a
TypeScript value, so the inferred type is the one to check.

Writing the result schema by hand, as Convex `returns` and tRPC `.output` do.
The query already says which columns come back, so a second definition drifts.

Putting the builder in the core entry. The browser bundle would carry it for
apps that never call it. The subpath keeps it out.

## Consequences

An app opts in per read. A column type `gen` does not know no longer validates
as a string, so a project that relied on that guess has to map the column or
accept `unknown`. Revisiting this means a query shape `selection` cannot
describe.
