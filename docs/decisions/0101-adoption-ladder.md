# 0101: Adopt better-supabase one rung at a time

- Status: accepted
- Date: 2026-10-25

## Context

An existing Supabase app should not have to rebuild its schema to use the library. ADR 0098 lets
blocks run over the app's tables per table, but per-table features (realtime, audit, search,
subjects) still need config entries, and the dashboard-created tables are found only through the
snapshot.

## Decision

Every rung is optional, independent and reversible, and doctor reports the rung of each table.

1. `init` on an existing project writes a config with no blocks, no SQL, and changes nothing in the
   database.
2. `gen` types every table the app has: repositories, validators and hooks.
3. `bsb table <t> enable|disable <feature>` adds or removes an `@bsb` tag in the table's comment
   (ADR 0102). The block files then render over that table.
4. `bsb add <block> --over <table>` runs a block over a table of the app's, with an entity rename.
5. Blocks that install their own tables can be added next to the app's at any time.

Detection reads the catalog (the live database or the PGlite load of the schema files), so a table
made in the dashboard is found like any other.

## Alternatives considered

- A one-shot migration to a library-owned schema: not reversible and not gradual.
- Feature flags in the config only: the config and the schema drift apart.

## Consequences

The docs page for existing apps is rewritten around the ladder, and an example starts as a plain
Supabase app.

## Status note

All four rungs ship: `init` detection with `--from`, `gen` helpers for every table, `@bsb` table
tags (ADR 0102), and `add <block> --over <table>`. `doctor --adoption` shows where each table
stands. The dashboard-table gap is closed in ADR 0098 by saving the snapshot.
