# 0880: Generate the CSV export route of an entity page

- Status: accepted
- Date: 2026-11-14

## Context

ADR 0855 added `entityList().export` and `exportResponse`, and left the route
to the app. ADR 0879 added the route manifest, so the generator can now write
it. EX-1210 also asked to move the eight blocks with an export onto it.

## Decision

`ENTITY_PAGE_OUTPUTS` gains `export-route` (`apiVersion` stays 1). A page that
sets `export: { filename?, columns?, maxRows? }` gets
`<appDir>/api/<name>/export/route.ts`: it parses the list query, then returns
`exportResponse(page, filename, { ...query, columns, maxRows })`. `columns`
defaults to the page's `columns`. The manifest entry gains an optional
`export` route, written only for these pages, so existing manifests stay valid.

The eight blocks keep their own exports. Payroll, OSCAL, SEPA, iCalendar,
promptfoo and the governance subject export write files that are not CSV rows of
`page`. The audit log's export pages by cursor and offset, reveals details and
writes NDJSON or OCSF. The data export is a job that writes an archive. None of
them can be a `page` with `exportCsv`, so none is migrated.

## Alternatives considered

- Give each block an `export` that wraps its format: it would hide that the
  filters and the format differ, and `exportCsv` has no format hook.
- Emit the route for every page: a route that streams up to 100000 rows is a
  decision the app makes per page.

## Consequences

An app gets a filtered CSV download from one descriptor field. A block whose
format is not CSV needs its own route; a format hook on `exportCsv` is the next
step if a second CSV-like format appears.
