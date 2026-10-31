---
"better-supabase": minor
---

Purchase bill lines and expense lines carry `dimensions`, so one bill or expense report can split its cost over several projects. A line of a purchase bill (`LineInput.dimensions`) overrides the bill's own `dimensions` per key, and an approved expense report books one expense line per distinct dimension set. `billableTime.projectCosts(projectId)` then counts each part on its project. `add_expense_line` and `update_expense_line` take a `dimensions` argument; a line table of yours without the column refuses it with `EXPENSE_DIMENSIONS_UNSUPPORTED`.

Run `better-supabase upgrade` and generate a migration. `invoice_lines` and `expense_lines` gain a `dimensions jsonb not null default '{}'` column, also over your own tables, and the two `add_expense_line` and `update_expense_line` functions get an eighth argument.
