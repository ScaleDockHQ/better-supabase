# 0501: Keep the legal entity number key swaps as `do` blocks until the owning modules render the key

- Status: accepted
- Date: 2026-11-08
- Amends: 0400

## Context

ADR 0400 counted the remaining top-level `do` blocks in the generated schema
files at four: one in the search module and three in the legal entities module.
The search block goes with the import guard work. The other three swap the
unique number key of the invoice, quote and order tables for a key that ends in
`coalesce(legal_entity_id, '0000...')`, so two entities can use the same
number.

## Decision

The three blocks stay. The unique keys belong to other modules' tables, and
their names and columns depend on what the app's own migrations created, so the
swap reads the catalog for each key when it runs. A schema diff can't write a
statement that depends on a name it doesn't know. `tests/sql/static-ddl.test.ts`
now keeps a reason for each file that still has blocks, fails when a reason
outlives its blocks, and holds the total at three once the search block is gone.

## Alternatives considered

Rendering the key in the owning modules when `options.on` names the table is the
way to remove the blocks: the invoice, quote and order modules would read the
legal entities option and write the coalesce key themselves. That changes three
modules and every app's key names, which the scale and imports work does not
need, so it waits.

## Consequences

The static-ddl total is three after the search block goes, which meets the
target. A later change that renders the keys in the owning modules removes the
reason and the baseline entry together.
