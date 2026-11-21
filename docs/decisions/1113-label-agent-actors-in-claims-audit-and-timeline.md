# 1113: Label agent actors on claims, audit rows and timelines

- Status: accepted
- Date: 2026-11-21

## Context

An `act` claim of kind `agent` was labeled an impersonation in audit rows.

## Decision

A profile `{ kind, name }` is stored on claims and carried in event data, and the timeline reads `actorKind` and `actorName` from it. `actor_kind()` returns `agent` for an `act` of kind `agent`. That is a behavior change for audit rows: they said `impersonation` before. The profile is a label and never grants access.

## Alternatives considered

A separate actors table was rejected: the label is data about one act.

## Consequences

Reports that grouped agent acts under impersonation change.
