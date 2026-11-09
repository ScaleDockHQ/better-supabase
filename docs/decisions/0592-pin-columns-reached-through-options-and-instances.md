# 0592: Pin columns reached through options and instances

- Status: accepted
- Date: 2026-11-09

## Context

`codemod naming` pinned an old column name only for `blocks.<name>.tables`. A
state machine whose history lives on an app table, and a block installed as an
instance, never got a pin. When `moduleContext` threw, the codemod skipped that
block and still exited 0, which is how a hiring `reviewer_user_id` pin was
missed on a 0.57 config that still had a refused key.

## Decision

`columnPins` also reads `options.machines.<name>.history`. When `actor` is
unset and the history table has `actor_user_id` but not `actor_id`, the codemod
writes `actor: "actor_user_id"` on that history object. The same pass runs for
`config.instances`. A block whose context throws becomes a review line, and
`codemod naming` exits `config_invalid`. `withColumnPins` writes only inside
the `blocks` object, then `instances`, one entry per line.

`codemod owned-columns` does not add a column that is the target of one of
those pending pins. It declares an optional column only when the snapshot
already has it, and otherwise names the `null` opt-out. Doctor BS625 reports a
`block-columns.sql` line that adds the new name beside a pin.

## Alternatives considered

Keep skipping a block whose context throws: the codemod looks successful and
the feature that reads the old column turns off.

Write every optional column into `block-columns.sql`: a declarative sync then
adds columns the database never had, which turns those features on.

## Consequences

An upgrade that still has a refused key stops at `codemod naming` instead of
shipping a schema that drops the old column. Revisit the history pin if the
state-machine actor default stops being `actor_id`.
