import type { RecipeSource } from "./types.ts";

import { WEB_APP } from "./types.ts";

const PROJECTS = `${WEB_APP}/src/features/projects/components`;

/**
 * Screens over the app's own tables, declared in your schema files, shown on
 * `projects` and `tasks` in the example.
 */
export const RECORD_RECIPES: readonly RecipeSource[] = [
  {
    slug: "record-grid",
    title: "Record grid",
    blocks: ["saved-views"],
    category: "App tables",
    kind: "screen",
    description:
      "An app table as a data grid with search, filters, saved views and bulk actions on the selected rows, including a Set field action.",
    web: {
      file: `${PROJECTS}/task-grid.tsx`,
      components: [
        "badge",
        "button",
        "dialog",
        "input",
        "select",
        "@reui/data-grid",
        "@reui/filters",
      ],
      glue: [],
    },
    note: "A copy of `@reui/data-grid` installed from ReUI 2.8.0 or earlier memoizes its context on `recordCount` but not on the rows, so an edit that keeps the row count (a status change, a renamed task) doesn't repaint the cells. Reinstall it with `npx shadcn add @reui/data-grid --overwrite`, or add `table.options.data` to the dependency list of the `value` memo in `DataGridProvider`.",
  },
  {
    slug: "record-form",
    title: "Record form",
    blocks: ["saved-views"],
    category: "App tables",
    kind: "component",
    description:
      "A create form whose inputs follow each column: a length limit for text, a select for options, a date input and a searchable picker for references.",
    web: {
      file: `${PROJECTS}/task-form-dialog.tsx`,
      components: ["button", "combobox", "dialog", "field", "input", "select"],
      glue: [],
    },
  },
  {
    slug: "record-page",
    title: "Record page",
    blocks: ["comments", "tags"],
    category: "App tables",
    kind: "screen",
    description:
      "One row as a page: its fields, the rows that reference it, and comments and tags once the table is a subject.",
    web: {
      file: `${PROJECTS}/project-page.tsx`,
      components: ["badge", "card", "skeleton"],
      glue: [],
    },
  },
  {
    slug: "record-board",
    title: "Record board",
    blocks: ["rank"],
    category: "App tables",
    kind: "screen",
    description:
      "An app table as a board with a column per option value, where dragging a card writes the value and its rank.",
    web: {
      file: `${PROJECTS}/task-board.tsx`,
      components: ["badge", "@reui/kanban"],
      glue: [],
    },
  },
  {
    slug: "record-calendar",
    title: "Record calendar",
    blocks: ["calendar"],
    category: "App tables",
    kind: "screen",
    description:
      "Rows on a month grid by a date column, with the month in the URL and a count of rows without a date.",
    web: {
      file: `${PROJECTS}/task-calendar.tsx`,
      components: ["badge", "button", "card"],
      glue: [],
    },
  },
  {
    slug: "record-timeline",
    title: "Record timeline",
    blocks: ["calendar"],
    category: "App tables",
    kind: "screen",
    description:
      "Rows as bars from a start date to an end date over four weeks, with a lane per assignee.",
    web: {
      file: `${PROJECTS}/task-timeline.tsx`,
      components: ["button", "card"],
      glue: [],
    },
  },
  {
    slug: "record-gantt",
    title: "Record Gantt chart",
    blocks: ["calendar"],
    category: "App tables",
    kind: "screen",
    description:
      "A row per record grouped by its parent, with a bar for its planned dates and a marker for rows without dates.",
    web: {
      file: `${PROJECTS}/task-gantt.tsx`,
      components: ["badge", "button", "card"],
      glue: [],
    },
  },
  {
    slug: "record-history",
    title: "Record history",
    blocks: ["versions"],
    category: "App tables",
    kind: "component",
    description:
      "Every version `subject.versions` kept of a row, with the fields each one changed and a restore per field.",
    web: {
      file: `${PROJECTS}/project-history.tsx`,
      components: ["badge", "button", "card", "empty"],
      glue: [],
    },
  },
  {
    slug: "upsert-import",
    title: "Upsert import",
    blocks: ["imports"],
    category: "App tables",
    kind: "component",
    description:
      "Paste CSV, map its columns, preview the rows it creates and changes, then upsert them on one of the table's unique sets.",
    web: {
      file: `${PROJECTS}/task-import-dialog.tsx`,
      components: [
        "alert",
        "badge",
        "button",
        "dialog",
        "field",
        "select",
        "skeleton",
        "textarea",
      ],
      glue: [],
    },
  },
];
