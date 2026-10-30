---
"better-supabase": minor
---

Block entity keys equal the entity's singular, and the subject types, hint codes and functions follow the new nouns (ADR 0130). Run `better-supabase codemod 0.47`; the [0.46 to 0.47 guide](https://bettersupabase.com/docs/migration/0.46-to-0.47) lists every rename. Old entity keys and subject types keep working until 0.48, with a warning, and doctor reports them (BS423).

| Before (0.46)                                              | After (0.47)                                                                             |
| ---------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| `blocks.tasks.entities.work_item`                          | `blocks.tasks.entities.task`                                                             |
| `blocks.activities.entities.engagement`                    | `blocks.activities.entities.activity`                                                    |
| `blocks.automations.entities.rule`                         | `blocks.automations.entities.automation`                                                 |
| `blocks.goals.entities.target`                             | `blocks.goals.entities.goal`                                                             |
| `blocks.compliance.entities.policy`                        | `blocks.compliance.entities.compliance_policy`                                           |
| `blocks.contracts.entities.obligation`                     | `blocks.contracts.entities.contract_obligation`                                          |
| `blocks.incidents.entities.postmortem`                     | `blocks.incidents.entities.incident_postmortem`                                          |
| `blocks.custom-fields.entities.field`                      | `blocks.custom-fields.entities.field_definition`                                         |
| generic keys (`request`, `entry`, `document`, `policy`)    | the block noun first (`leave_request`, `knowledge_document`)                             |
| subject types `work_item`, `engagement`, `policy`          | `task`, `activity`, `compliance_policy`                                                  |
| `WORK_ITEM_*`, `ENGAGEMENT_*`, `RULE_*`, `TARGET_*`        | `TASK_*`, `ACTIVITY_*`, `AUTOMATION_*`, `GOAL_*`                                         |
| `POLICY_*`, `OBLIGATION_*`, `POSTMORTEM_*`, `HIRING_JOB_*` | `COMPLIANCE_POLICY_*`, `CONTRACT_OBLIGATION_*`, `INCIDENT_POSTMORTEM_*`, `JOB_OPENING_*` |
| timeline `ACTIVITY_FORBIDDEN`                              | `TIMELINE_ENTRY_FORBIDDEN`                                                               |
| `create_work_item`, `log_engagement`, `save_target`        | `create_task`, `log_activity`, `save_goal`                                               |
| `publish_policy`, `save_obligation`, `save_postmortem`     | `publish_compliance_policy`, `save_contract_obligation`, `save_incident_postmortem`      |
| `workItemChecklistBinding`                                 | `taskChecklistBinding`                                                                   |

- `ENTITY_KEY_RENAMES`, `SUBJECT_TYPE_RENAMES`, `HINT_RENAMES` and `legacyHintOf` are exported for code that maps stored names.
- `upgrade` renders a data step in the tasks, activities and compliance modules that moves stored subject types to the new ones in every installed subject type column. The subject functions accept the old types until 0.48.
- A `@bsb subject` tag that declares a type an installed block registers now fails with an error naming the table, instead of being skipped. An app whose own table is the `task` subject keeps the block on `names: { task: "work_item" }`.
- Tables and events keep their names on an install that doesn't rename the entity: the tasks block still writes `work_items` and emits `work_item.created`.
