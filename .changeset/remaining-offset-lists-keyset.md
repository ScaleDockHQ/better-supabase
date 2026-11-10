---
"better-supabase": minor
---

`list_checkout_sessions`, `list_agent_mandates`, `list_pick_lists`, `list_appraisals`, `list_usage_rights` and `list_maintenance_plans` page through the keyset list template, with list indexes that end in the id. `checkout.sessionPage`, `checkout.mandatePage`, `warehouse.pickListPage`, `appraisals.appraisalPage`, `dam.rightPage` and `maintenance.planPage` return `{ items, hasMore, nextCursor }`, and `total` when asked.

Migration guide:

| Before                                                             | After                                                                          |
| ------------------------------------------------------------------ | ------------------------------------------------------------------------------ |
| `listRights({ offset: 100 })`                                      | Still works. Keep it where you show page numbers.                              |
| `listRights({ offset, after })`                                    | Refused with an invalid error. Pass one of them.                               |
| Deep paging with `offset`                                          | `rightPage({ after: page.nextCursor })`.                                       |
| `listPlans({ due: true, limit: 20 })` returning fewer than 20 rows | The `due` filter now runs inside the query, so a page holds `limit` due plans. |

The same applies to the other five lists and their page methods. Run `supabase db diff` to pick up the new list indexes. `list_import_issues` and `list_import_diff` keep their positional arguments.
