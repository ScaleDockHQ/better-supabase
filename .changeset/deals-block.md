---
"better-supabase": minor
---

The `deals` SQL module and `better-supabase/blocks/deals` add deals on pipelines. Installing deals binds the `deal` type in the pipelines module with a Qualified to Closed won or Closed lost ladder. A deal has an amount in minor units, a company and contacts from `config.subjects`, a team, line items, a motion, a priority, a forecast call, flags and a next step. `update(changes)` applies grid edits one by one and returns the refused ones with their hint. The table refuses edits to a locked deal, keeps the open date, counts close-date slips and stamps `closedAt` with `deal.closed`. `win`, `lose` and `reopen` move a deal through its pipeline's stages, `forecast` returns won, commit, best case, pipeline, not called and later with attainment and gap, and `health` flags rotting, slipped, missing and overdue next steps.

Line items share one shape across blocks: `set_<record>_lines` replaces a record's lines and a trigger keeps its list, discount, subtotal, tax and total.
