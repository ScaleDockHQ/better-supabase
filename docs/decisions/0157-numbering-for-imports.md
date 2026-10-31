# 0157: Numbers are scoped per legal entity and an import keeps its historical numbers

- Status: accepted
- Date: 2026-10-31

## Context

An ERP import brings invoices, credit notes and quotes that already have
numbers. Those numbers must survive, the counters must continue above them, and
two legal entities of one organization (ADR 0142) number independently. ADR
0141 gives an import run a mode (`better_supabase.import_run()`) that other
code can test.

## Decision

- `number_sequences` gains a `scope` text column and its key becomes
  `(tenant, entity, scope, period)`. The scope is the legal entity as text, and
  the empty text for the default entity. The nullable `legal_entity_id` that
  `options.on: ["numbering"]` adds stays unused, because a nullable column
  cannot be in a primary key.
- An entity sets `series: "kind"` (default) or `"none"`, and `scopeColumn` for a
  table with a legal entity column. Credit notes keep their own series by
  default.
- A fixed number is accepted only while `import_run()` is set. Invoices and
  credit notes take it as the `fixed_number` argument; every other numbered
  entity takes it from `set_fixed_number(entity, number)`. Either way the
  counter moves up to it (`register_fixed_number`). Otherwise the call fails with
  `NUMBER_FIXED_FORBIDDEN`.
- `sync_number_sequences(tenant, entity, scope)` returns `{ synced, mismatched }`.
  It never rejects a number. Numbers outside the current format are listed in the
  result and as warnings on the import run.
- On an app's own sequences table, `upgrade` replaces the keys that lack the
  scope with one unique index over tenant, entity, scope and period.

## Alternatives considered

- **Reuse `legal_entity_id` as the key.** A primary key cannot hold a nullable
  column, and a sentinel uuid would leak into the data.
- **Reject numbers outside the format.** Historical numbers rarely match the new
  format, and rejecting them fails the import on its own data.
- **One function for every entity.** Invoices and credit notes issue in the same
  call as the number, so the argument is the shortest path for them.

## Consequences

- `sync_number_sequences` returns jsonb instead of an integer, and it takes a
  third argument.
- `next_number` and `preview_number` take `p_scope`, with an empty default, so
  existing callers keep working.
- Quotes, orders and the other entities have no legal entity yet, so they sit in
  the empty scope.
- A table trigger still accepts a service-role write with its own number outside
  an import run. Only the explicit fixed-number paths need import mode.
