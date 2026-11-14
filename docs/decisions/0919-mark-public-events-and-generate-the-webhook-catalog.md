# 0919: Mark public events and generate the webhook catalog

- Status: accepted
- Date: 2026-11-14

## Context

About fifteen blocks emit events that apps forward as outgoing webhooks, and no manifest says which events a subscriber may receive. An app listed event types by hand and could expose an internal one such as `organization.switched` (EX-1320).

## Decision

`event<T>({ public: true })` marks an event in `defineEvents`, which records the types in `Events.public`. `mergeEvents` keeps them. `webhookEventCatalog(blocks)` in `src/blocks/event-catalog.ts` returns the marked events by block and type, and `pnpm catalog` writes the same list into the entity matrix of the audit report. `organizations`, `shipments`, `invoices` and `orders` mark their events; other blocks follow as their webhook use is confirmed. Unmarked events stay internal, so nothing changes for an app that ignores the catalog.

## Alternatives considered

A separate `webhooks` field on the manifest duplicated the event list and drifted. A name pattern such as `*.created` exposed events that carry internal data.

## Consequences

Marking an event is a one-line change next to its declaration. A block that adds a public event has it in the catalog and the docs with no other edit. A test checks that every marked type is a declared type.
