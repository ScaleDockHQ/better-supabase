# 1029: A format hook on the entity export

- Status: accepted
- Date: 2026-11-15
- Amends: 0855, 0880

## Context

ADR 0855 streams an entity's rows as CSV, and ADR 0880 said a format hook on
`exportCsv` was the next step once a second line-oriented format appeared.
EX-1210 asked to move the blocks that export onto the one call. Of the eight
exports, only the audit log writes line-oriented rows (NDJSON), and it pages by
cursor and offset and reveals details, so it is not a `page` either.

## Decision

`ExportOptions` gains `format`, an `ExportFormat` with a `contentType`, an
optional `header(columns)` and `rows(items, columns, escapeFormulas)`.
`csvFormat` stays the default and `ndjsonFormat` is the second format.
`exportResponse` answers with the format's content type. The helpers are
exported from `better-supabase/blocks`.

The formats that write a whole document (payroll, OSCAL, SEPA, iCalendar,
promptfoo, the governance subject export and the data export archive) stay
their own exports. A hook that takes a header and rows cannot write a document
with a root element or a footer, and widening it for them would turn `export`
into a second `page`.

## Alternatives considered

- A `footer` and a `start` hook, so XML formats fit: no block asked for a
  streamed document through `page`, and each of them builds from other reads.
- Rename `exportCsv`: the name is public and `exportRows` would only be an alias.

## Consequences

An app that wants NDJSON or TSV from a list passes `format`. EX-1210 is fixed:
the one call covers the line-oriented formats and the remaining exports are
documented as final in their own format.
