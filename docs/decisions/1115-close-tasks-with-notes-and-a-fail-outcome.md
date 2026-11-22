# 1115: Close tasks with notes and a fail outcome

- Status: accepted
- Date: 2026-11-21

## Context

Workers report why they stopped, and a failure is not a cancellation to the user.

## Decision

`complete`, `cancel` and `fail` take a `note`, stored in `close_note`. `fail` lands in the canceled category with the close reason `failed`. With `canceled: null` in the pipeline options there is no such stage, so `fail` raises `TASK_OUTCOME_UNAVAILABLE`. A call with only a stage keeps the old settle path for compatibility.

## Alternatives considered

A new failed category was rejected: it changes every pipeline.

## Consequences

Adopters without a canceled stage can't use `fail`.
