# 0991: Start workflow runs from block events with an event trigger

- Status: accepted
- Date: 2026-11-14

## Context

The trigger node's `trigger: "event"` option was only a label: the engine had
no `event` trigger kind, so a definition could not start from something that
happened in the app (finding EX-201).

## Decision

`workflow_triggers.kind` gains `event`, with the block event type or a
`prefix.*` pattern in `config.event`. The service-role function
`workflow_event_targets(event, tenant)` returns the enabled triggers that
match. `builder.triggers.fire(event)` starts one run per match, keyed on the
trigger and the event so a redelivered event starts one run, and
`subscribeEventTriggers(betterSupabase, builder)` calls it from
`betterSupabase.events.on("block", ...)`. The subscriber only observes
(invariant 5): a failed start goes to an `onError` callback, and `fire` never
throws. A tenant's definitions fire only for that tenant's events; a system
definition fires for all.

## Alternatives considered

An outbox consumer: it sees events of every process, but it needs a consumer
route and polling, and the automations block already covers that case. The
in-process subscriber is the same hook apps use for other observers. A new
`apiVersion` was not needed: the trigger kind list is a check constraint, not
an extension interface.

## Consequences

The subscriber reacts to events its own process emits. Events written by
another process reach a definition through an automation on the outbox. An app
whose own enum types the trigger kind must add `event` to it; the migration
adds the value to the module's check constraint.
