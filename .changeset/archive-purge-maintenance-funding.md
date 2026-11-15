---
"better-supabase": minor
---

Breaking: maintenance plans and funding claims can be archived and restored,
and their hard delete is `purge`, behind `permissions.purge` (ADRs 1043 and
1044). An archived maintenance plan is never due and opens no work order. Only
a claim the funder answered is archived; a draft claim is purged.

| Before                              | After                                                |
| ----------------------------------- | ---------------------------------------------------- |
| `maintenance.deletePlan(id)`        | `maintenance.purgePlan(id)`                          |
| `delete_maintenance_plan(id)` (SQL) | `purge_maintenance_plan(id)`                         |
| event `maintenance_plan.deleted`    | event `maintenance_plan.purged`                      |
| `funding.deleteClaim(id)`           | `funding.purgeClaim(id)`                             |
| `delete_funding_claim(id)` (SQL)    | `purge_funding_claim(id)`                            |
| event `funding_claim.deleted`       | event `funding_claim.purged`                         |
| `list_funding_claims(tenant, ...)`  | `list_funding_claims(tenant, ..., include_archived)` |

Run `better-supabase upgrade` and apply the migrations, which add
`archived_at`. See the 0.66 to 0.67 guide.
