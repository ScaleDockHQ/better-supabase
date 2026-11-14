# 0869: Generate columns, a detail frame and forms from the entity page

- Status: accepted
- Date: 2026-11-14

## Context

Lane M1 (ADR 0859) generates the list query of an entity page. The columns, the
detail page and the create and edit forms stayed hand-written per entity
(EX-1262, EX-1263, EX-002), and the form fields drifted from the action schemas
they submit to (EX-806). ADR 0859 reserved `columns` and `sections` in the
descriptor for this lane, and the block manifest already carries the JSON
Schemas of each block's input and change types (`entitySchemas`).

## Decision

Three outputs join `ENTITY_PAGE_OUTPUTS` after `scale-test`, with
`apiVersion: 1`. The descriptor and `EntityPageOutput` do not change, so there
is no `apiVersion: 2`.

- `columns` writes `pages/<name>.columns.ts` when the page sets `columns`. Each
  entry is an `EntityColumn`: the row `key`, the database `column`, a `label`, a
  `kind` and, when the entity declares one with the same name, its `sort` and
  `filter`. The kind comes from the block's input or change schema and falls
  back to the name (`...At` is a datetime, `...On` a date, `...Id` a uuid). A
  name that is not a column of the table stops `gen` with `config_invalid`.
- `detail` writes `pages/<name>.detail.ts` when the page sets `sections`: an
  `EntityDetail` with `<route>/:id`, the sections with labels and `href(id)`.
- `forms` writes `pages/<name>.form.ts` for an entity whose block exports an
  input or change schema: `<name>CreateForm` and `<name>EditForm`, each a
  `defineEntityForm` over the schema's fields. Read-only and `json` fields are
  left out.

`defineEntityForm` and the types `EntityColumn`, `EntityDetail`,
`EntityDetailSection`, `EntityFieldKind`, `EntityForm`, `EntityFormField` and
`EntityFormParse` join `better-supabase/list`. `parse` turns `FormData` or a
record of text into the action's input and returns issues with field paths. The
action's schema stays the authority; the form check only names what a user can
fix.

The outputs write plain `.ts` data and no JSX, so they hold no choice of grid,
router or form library. The app maps `columns` to its grid, `sections` to its
tabs and `fields` to its inputs.

## Contract for lane M3

M3 appends its outputs to `ENTITY_PAGE_OUTPUTS` after `forms` and reads
`ResolvedEntityPage`: `page.area` and `page.seed` for navigation and seed rows,
`entry.table` and `entry.surface` for the table and its list surface, and
`entry.schemas` for the block's input schemas. An output writes beside the list
module with `context.pagesDir` and `<name>.<part>.ts`. Navigation and the route
manifest may import `<name>Detail.href` and the first `columns` entry rather
than recomputing them. A new descriptor key is added to `EntityPage`, the valibot
schema in `src/cli/config-schema-entity-page.ts` and the docs table together.

## Alternatives considered

- Emit TanStack `ColumnDef` and React form components. This ties the generator
  to the example's libraries and needs JSX in every app. Data plus a typed
  helper works for any grid.
- Derive columns from every table column. A list shows a chosen few, in an
  order only the app knows, so `columns` stays explicit.
- Add a `forms` key to the descriptor. The schema decides the fields, so a key
  would only repeat it.

## Consequences

A page declares its columns and sections in the descriptor and gets typed data
for the grid, the record frame and both forms. A block upgrade that changes an
input schema changes the form on the next `gen`. EX-033 is only partly met: a
column header can select a named sort, but a free multi-column sort still needs
a `freeSort` list. EX-034 is a ReUI `Filters` behavior and stays open.
