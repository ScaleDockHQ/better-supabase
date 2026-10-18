---
"better-supabase": minor
---

`better-supabase scaffold screens <table>` writes Next.js pages for an app table: a list, a create form with an input per column (from its type, `format`, `options`, `min` and `max`, and a select of rows for a reference to another app table) and a detail page. The pages read and write through the generated repository with `bs`, so RLS checks every request, and each file is written once and then kept as yours. `--base-path` sets the route, `/<table>` by default. The command refuses a table outside `appTables`, a table with `scope: "none"` and a required column the form has no input for.

The UI recipes gain an App tables group: `record-grid`, `record-form`, `record-page`, `record-board`, `record-calendar`, `record-timeline` and `record-gantt`, built on projects and tasks in the Next.js example. Create lists the `scaffold screens` command for each app table in Get code, and its AI instructions link the record recipes once the design has an app table.

Migration: none.
