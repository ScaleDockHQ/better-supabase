# 0021: Order rows with base-62 fractional rank keys

- Status: accepted
- Date: 2026-10-13

## Context

Boards, pipelines, tag lists and custom field lists need a user-defined
order. Tags and custom fields stored an integer `position`, so moving one
item renumbered every item after it, two concurrent moves could write the
same position, and a drag between two rows needed a transaction over the
whole list. Kanban recipes (CRM pipelines, project boards) also move a card
to another column in the same drag, and that column is often a state-machine
status whose transitions the database enforces.

## Decision

Order is a `text collate "C"` column of base-62 keys (`0-9A-Za-z`, in byte
order). A key is never empty and never ends in `0`, so there is always a key
between two keys. `rankBetween` (`src/core/rank-keys.ts`, no imports so every
entry can use it without pulling in the error helpers) and the SQL
`rank_between` implement the same steps, and both are tested against
`tests/core/fixtures/rank-vectors.json`. `rankKeys(n)` and `rank_key(nth,
total)` produce evenly spaced keys of the smallest width.

The `rank` SQL module serves subjects with a `rank` entry in
`config.subjects` (ADR 0020). `move(subject_type, subject_id, previous_id,
next_id, to_group)` is security invoker: it checks `can_subject` for
`update`, rejects neighbours from another tenant or group, and writes the key
and the group column in one update, so the table's policies and a
state-machine trigger on the group column apply. When a key passes 24
characters and the `jobs` module is installed, it enqueues `rank.rebalance`.
`rebalance_ranks` is security definer and service only; it rewrites one
tenant's group to `rank_key` keys in the same order.

Tags and custom fields keep their own `rank` column instead of depending on
the module: creating a definition appends a key with an inline SQL
expression over the last key, and `rank_tag` and `rank_field_definition`
save a key the client computes with `rankBetween` from the neighbours' keys.
Both modules move to version 2, whose upgrade backfills keys in the old
`position` order and drops `position`.

## Alternatives considered

- **Keep integer positions with gaps.** Gaps run out under repeated moves to
  the same spot and still need renumbering, only less often.
- **A dependency such as `fractional-indexing`.** It would be a runtime
  dependency (invariant 1), and Postgres would still need its own copy of the
  algorithm.
- **A `subject.moved` audit event from `move`.** Audit writes need security
  definer, and `move` must run as the caller so policies and the
  state-machine trigger see the change. The state machine's own
  `status.changed` event covers the group change.
- **Tags and custom fields on top of the rank module.** It would make
  `subjects` and `access` a requirement for two modules that work without
  them today.

## Consequences

A move writes one row. Keys grow by about one character per insert at the
same spot, which the rebalance job bounds. Adopted tables need a byte-order
collation on the rank column, or comparisons in Postgres and TypeScript
disagree. Adopt configs that mapped `position` for tags or custom fields map
`rank` instead. Revisit if a list needs more than about 62^24 inserts between
two rebalances.
