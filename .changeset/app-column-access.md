---
"better-supabase": minor
---

App table columns take `access: "read"` or `access: "server"`. `sql sync` then grants `select`, `insert` and `update` on the columns signed-in users may use, by name, and the `<table>_view` lists only the readable columns. `gen` marks a server column `selectable: false`, so a default select leaves it out and the row type makes it optional; select it by name with the service role client. `appTables` refuses a required restricted column without a default, and a server column used as the subject title, a search column, a rollup or lookup source, or in `events.include`. Tightening a column's access is a breaking change in the design diff, and Create design codes with `access` use format 5.

`doctor` counts column grants for BS106, so a table whose grants list columns no longer reports "Table not granted to the Data API".
