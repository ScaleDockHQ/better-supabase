---
"better-supabase": minor
---

Event verbs, hint prefixes and block keys follow one rule, and `pnpm check:naming` enforces it (ADR 0699). The SQL modules `webhooks-out` and `webhooks-in` are the blocks `webhooks` and `incoming-webhooks`, ten hint prefixes carry the block they come from, and two events use the lifecycle verb `updated`. Run `better-supabase codemod naming` to rename the config keys, then `better-supabase upgrade` and `db diff`; the data migration renames the block's row in `better_supabase.blocks`, so installed modules keep their version and mode. Outbox rows and logged errors keep the names they were written with.

| Old                                               | New                                              |
| ------------------------------------------------- | ------------------------------------------------ |
| `blocks["webhooks-out"]`, `blocks["webhooks-in"]` | `blocks.webhooks`, `blocks["incoming-webhooks"]` |
| `message.edited`                                  | `message.updated`                                |
| `drive_node.document_saved`                       | `drive_node.document_updated`                    |
| `EVAL_*` (ai-evals)                               | `AI_EVAL_*`                                      |
| `HOSTNAME_*` (domains)                            | `DOMAIN_*`                                       |
| `SUPPORT_*` (impersonation)                       | `IMPERSONATION_*`                                |
| `CARE_*` (clinical-decision-support)              | `DECISION_SUPPORT_*`                             |
| `BOM_*` (manufacturing)                           | `MANUFACTURING_BOM_*`                            |
| `SSF_*` (security-events)                         | `SECURITY_EVENT_*`                               |
| `TIMESHEET_*` (time-entries)                      | `TIME_ENTRIES_TIMESHEET_*`                       |
| `FIELD_*` (custom-fields)                         | `CUSTOM_FIELD_*`                                 |
| `PRESCRIPTION_*` (e-prescribing)                  | `E_PRESCRIBING_*`                                |
| `WEBHOOK_IN_*` (incoming-webhooks)                | `INCOMING_WEBHOOK_*`                             |

The type `DateBucketArgs` (exported from `better-supabase/list`) is now `DateBucketOptions`, because `Args` is a banned suffix. `codemod naming` rewrites it.
