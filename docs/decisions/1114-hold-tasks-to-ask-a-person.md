# 1114: Hold tasks to ask a person

- Status: accepted
- Date: 2026-11-21

## Context

A worker that needs an answer should stop its task without losing it.

## Decision

`hold_task` sets `held_at` and `hold_kind`, sends the note through messaging with mentions, and moves the task to `options.hold.stage` when set. A hold refuses claims (`TASK_HELD`). A manual move into the hold stage is not a hold; a manual move out of it while held clears the hold. `askUserIds` must be able to read the task, checked with `can_user`.

## Alternatives considered

A task state was rejected: holds are orthogonal to the pipeline stage.

## Consequences

Messaging is needed for the note (`TASK_HOLD_MESSAGING_MISSING`).
