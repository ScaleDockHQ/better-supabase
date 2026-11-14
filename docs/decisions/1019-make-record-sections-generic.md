# 1019: Make the record sections generic over a subject

- Status: accepted
- Date: 2026-11-14

## Context

The comments, files, relations and version history of the example lived under
`features/customers` and took a customer id. The deal desk and the contact pages
needed the same four sections, and each copy would have bound the same blocks
again. `gen` emits a `records/<type>.ts` only for subjects no binding block
registers, so `deal` has no generated record type to share.

## Decision

`features/records` holds the sections. `record-pages.ts` builds one record type
per subject (`customer`, `company`, `person`, `deal`) from a single
`sectionRecord(type)` factory with the comments, attachments and relations
bindings. `records-queries.ts` and the section components take a
`RecordSubject`, and `RecordFiles`, `RecordRelations`, `RecordHistory` and
`RecordDiscussion` render for any of them. Server Actions must be module
exports, so `records-actions.ts` exports one action per subject and write, and
`records-action-map.ts` gives client components the map by subject type.
Versions stay on customers, the only subject that binds the versions block.

The recipes `attachments-uploader`, `related-items-panel` and `subject-timeline`
now point at the moved files, and `pnpm recipes` regenerated their pages.

## Alternatives considered

Copying the customer sections per subject was fast but left four copies of every
fix. Generating a record type for `deal` would have changed what `gen` emits for
every app, which is a library change this lane does not need.

## Consequences

A new subject adds one line to `RECORD_TYPES`, one to `recordPages` and its
actions. The recipe sources moved, so a reader of the published recipe sees the
generic component. Revisit when `gen` can emit a record type for a subject with a
binding block.
