# 0146: Number controlled documents per type

- Status: accepted
- Date: 2026-10-30

## Context

ADR 0133 numbers every controlled document from one `DOC-{n:5}` sequence per
organization and left per-type formats such as `SOP-{n:4}` for later. The
numbering block takes one format per entity, so a format keyed by a row value
would also share one counter across types.

## Decision

- A type in `blocks.drive.options.control.types` is a string or
  `{ name, numberFormat }`. A type with a `numberFormat` gets its own numbering
  entity, `<drive_document>_<type>`, contributed to the numbering block with
  `period: "none"`, so each type counts from 1.
- Types without a `numberFormat` keep the shared `DOC-{n:5}` entity, so
  existing documents and the existing counter don't change.
- `drive_document_save` picks the entity and format from the document type in
  SQL. A document keeps its number when its type changes.

## Alternatives considered

- **A format map keyed by a row value inside one numbering entity.** The
  counter would be shared, so `SOP-0001` would be followed by `POL-0002`.
- **Renumber on a type change.** A released document's number is referenced in
  other records and must not change.

## Consequences

- A format is validated when the SQL is rendered: it needs `{n}` and at most
  80 characters.
- Changing a type's `numberFormat` later affects only new documents.
