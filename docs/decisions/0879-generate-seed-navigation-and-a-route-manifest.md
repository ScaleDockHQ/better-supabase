# 0879: Generate seed rows, navigation and a route manifest from the entity page

- Status: accepted
- Date: 2026-11-14

## Context

Lane M2 (ADR 0869) generates the columns, detail frame and forms of an entity
page. Demo rows (EX-1264), the nav item and the route manifest (EX-1267) and the
message keys of a page (EX-1268) stayed hand-written per page. ADR 0869 reserved
`area` and `seed` in the descriptor and set the contract: an output reads
`ResolvedEntityPage`, writes beside the list module with `context.pagesDir` and
`<name>.<part>.ts`, and may import `<name>Detail.href` and the first `columns`
entry.

## Decision

Three outputs join `ENTITY_PAGE_OUTPUTS` after `forms`, with `apiVersion: 1`.
The descriptor, its valibot schema and the docs table do not change, so there is
no `apiVersion: 2`.

- `seed` writes `pages/<name>.seed.ts` when the page sets `seed`: `<name>Seed`
  with the table, the tenant column, the `tiers` (default `demo`) and `demo` rows
  (default 10, at most 500). A row is keyed by database column and holds the
  required, writable fields of the block's input schema that are columns of the
  table. Values come from the field's kind and bounds and count forward from a
  fixed day, so the same descriptor gives the same rows. A page that sets `seed`
  while its block exports no fitting input schema stops `gen` with
  `config_invalid`.
- `navigation` writes `pages/<name>.navigation.ts` when the page sets `area`:
  `<name>Nav` with the area, a label, the list href, `recordHref` (imports
  `<name>Detail.href`) and `titleKey` (the first `<name>Columns` entry).
- `manifest` writes `pages/routes.manifest.ts`: `entityRoutes`, one entry per
  page with the list route, the API route, the detail route and `messageKeys`
  for the title, columns, facets, sections and form fields.

`EntitySeed`, `EntitySeedValue`, `EntityNavItem` and `EntityRouteEntry` join
`better-supabase/list` as types. The outputs write plain data and no SQL, JSX or
translation files.

## Alternatives considered

- Write seed SQL. The seed tiers live in `supabase/seeds`, which the app owns,
  and a rows module lets the app insert through its own client or a script.
- A `nav` key in the descriptor. `area` already names the group and the label
  comes from the page name, so a key would repeat it.
- Fail on an empty translation inside `gen`. `gen` does not read the app's
  message files, so the keys are data for the app's own check.

## Consequences

A page gets its nav item and its place in one manifest from its descriptor. EX-1264, EX-1267
and EX-1268 are partly fixed: the coverage map is still hand-edited, the example's
seed rows have not moved onto `<name>.seed.ts`, and nothing yet fails on an empty
`msgstr`. Lane M4 finishes them in the example.
