# 0561: Load the board view and the task form on use

- Status: accepted
- Date: 2026-11-08
- Amends: 0480, 0483

## Context

The analyzer shows what each route carries over the shared floor of about 1.29
MB raw. `/projects` (1991225 bytes) and `/projects/[id]` (1504579) were the two
largest routes that paid for code the visitor might never use:

- `TaskViews` imported `TaskBoard` for every view, so the table, calendar,
  timeline and Gantt views downloaded the kanban and `@dnd-kit` code (about 62 KB
  in the analyzer).
- `TaskFormDialog` (a dialog, a select and two comboboxes) shipped on both pages
  although it opens on a click. `projects/[id]` had no other use of those
  `@base-ui/react` parts.

A `await import()` in a server component does not help: the client reference
manifest still lists every client module the page imports, and the first load did
not change (measured at +10 bytes).

## Decision

- `task-board-lazy.tsx` loads `TaskBoard` through `React.lazy` inside a client
  component with a skeleton, so only the board view downloads the kanban code.
- `task-form-dialog-lazy.tsx` renders the closed "New task" button and loads the
  form through `LazyOnIntent` on the first hover, focus or click (the pattern of
  ADR 0483). `project-page.tsx` uses it.
- `/projects` keeps the static `TaskFormDialog`. Making it lazy there saved 19 KB
  more but moved modules between shared chunks and raised the raw size of 128
  other routes by 137 bytes each, which is above the 128 byte slack of
  `tests/next-build`.
- The advanced filters and the data grid stay as they are: they are the table
  view's own code, and the record-grid recipe is cut from `task-grid.tsx`.

## Measured

First load, raw bytes: `/projects` 1991225 to 1923708 (minus 67517),
`/projects/[id]` 1504579 to 1443751 (minus 60828). No other route changes by more
than 8 bytes. The customers dialogs (4.5 KB, ADR 0483) are not worth a wrapper.

## Alternatives considered

- Lazy-loading the boards of `crm/deals`, `work` and the other kanban routes.
  Rejected: the board is the page there, so the code downloads right after the
  paint and the first load number drops without the visitor saving anything.

## Consequences

A click on "New task" before the form arrives opens it once it mounts. The loading
specs for `/projects` and `/projects/[id]` run against the native stack.
