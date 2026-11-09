# 0540: Count object levels in `renameBlock`, not wrappers, and cap the depth at 4

- Status: accepted
- Date: 2026-11-08
- Amends: 0451

## Context

`RenamedType` in `blocks/rename-block.ts` follows a block client down a fixed
number of levels and renames the keys it finds. Every function, promise, result
and array added one level, so a row reached through `client.list()` used four of
the six levels before its first key. ADR 0451 tried a cap of 4 and recorded that
it failed two cases in `rename-block.test-d.ts`, and that 5 failed "renames the
column a change names", so the cap stayed at 6.

## Decision

The depth counts the levels of objects, not the wrappers around them. A
function, a `Promise` and an `AsyncResult` keep the depth of what they wrap, and
an array keeps it too unless its elements are arrays (so a self-referencing
array type still ends). `MaxDepth` is 4: the client, a row, a nested row and a
change record.

With that rule the cap of 4 passes every case in
`tests/blocks/rename-block.test-d.ts`, including the `changes[number].field` case
that failed at 5 under the old rule. `pnpm typecheck` of the package and the
TypeScript 6, 7 and 7.1 matrix pass unchanged.

## Alternatives considered

- Keep 6, as ADR 0451 did. It leaves the cost of the deepest instantiation in
  every renamed block for no case that needs it.
- Raise the cap to fit the failing case. The failures came from counting
  wrappers, so a higher cap hides the cause.

## Consequences

A renamed client's types stop instantiating two levels earlier. The public
behavior is the same for every block in the repo; a client type with more than
four nested object levels below its methods now keeps its original keys at the
fifth, which no block has. Revisit it if a block adds a fifth level.
