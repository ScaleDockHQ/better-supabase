---
"better-supabase": minor
---

The `guests`, `dispatch`, `incidents`, `approvals`, `assets`, `cases` and `deadlines` blocks gain `page`, `facets` and `count` through the shared list surface (audit lane G7). Each takes the same filters, sorts and `q` that its manifest declares, and rejects an undeclared one with `invalid_input`. `list` and the old SQL functions are unchanged, and the migration only adds functions, so apply it in any order with the client upgrade.

| Block       | New client calls                     | New SQL function                 |
| ----------- | ------------------------------------ | -------------------------------- |
| `guests`    | `page`, `facets`, `count`, `get(id)` | `page_guests`, `get_guest`       |
| `dispatch`  | `page`, `facets`, `count`            | `page_work_orders`               |
| `incidents` | `page`, `facets`, `count`            | `page_incidents`                 |
| `approvals` | `page`, `facets`, `count`            | `page_approvals`                 |
| `assets`    | `page`, `facets`, `count`            | `page_assets`                    |
| `cases`     | `page`, `facets`, `count`            | `page_cases`                     |
| `deadlines` | `page`, `facets`, `count`, `get(id)` | `page_deadlines`, `get_deadline` |

`approvals.page` has no `tenantless` option; requests without an organization stay on `list`. `incidents` takes the organization on every call.
