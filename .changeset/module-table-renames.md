---
"better-supabase": minor
---

Module tables follow the naming convention (ADR 0130): a table is its entity's plural, or starts with its entity's singular. Run `better-supabase upgrade` and generate a migration; it renames each table in place with its indexes, policies, triggers, constraints and sequences, so no row moves and no table is dropped. The [0.46 to 0.47 guide](https://bettersupabase.com/docs/migration/0.46-to-0.47#table-names) lists every table.

| Before (0.46)                                                    | After (0.47)                                                           |
| ---------------------------------------------------------------- | ---------------------------------------------------------------------- |
| `work_items`, `work_item_assignees`, `work_item_checklist_items` | `tasks`, `task_assignees`, `task_checklist_items`                      |
| `engagements`, `targets`, `policies`                             | `activities`, `goals`, `compliance_policies`                           |
| `rules`, `rule_defaults`, `rule_versions`                        | `automations`, `automation_defaults`, `automation_versions`            |
| `leases` (idempotency), `lease_agreements`                       | `idempotency_leases`, `leases`                                         |
| `organization_domains`, `organization_sso_providers`             | `sso_domains`, `sso_providers`                                         |
| `status_pages`, `status_components`                              | `incident_status_pages`, `incident_status_components`                  |
| `fulfillments`, `shipping_rates`, `kitchen_stations`             | `order_fulfillments`, `order_shipping_rates`, `order_kitchen_stations` |
| `activity_entries`, `ai_message_embeddings`                      | `timeline_entries`, `memory_message_embeddings`                        |

- `TABLE_RENAMES` is exported for code that maps stored table names.
- Tables you adopted through `blocks.<name>.tables`, and the tables of an entity you renamed, keep their names. Foreign key columns such as `work_item_id` keep theirs too.
- `codemod 0.47` lists queries on an old `better_supabase` table for review.
- The rename steps also rename the constraints and owned sequences that carry the old table name, so a schema diff after `upgrade` finds no drop and create pairs.
- `compliance` moves to version 3. An install at version 1 first moves its policy acknowledgements onto the `acknowledgements` block, reading `policies`, and then renames the table. An upgrade step that runs before a table rename always reads the table by its old name.
