---
"better-supabase": major
---

Finish the renames that the naming convention left open, and give each block manifest a
`description`.

| Old                                                                   | New                                                           |
| --------------------------------------------------------------------- | ------------------------------------------------------------- |
| operation actions `view`, `viewAll`, `edit`, `admin`, `viewSensitive` | `read`, `readAll`, `write`, `manage`, `readSensitive`         |
| `EngagementNotes.actionItems` and the column `action_items`           | `actionTaskIds` and the table `activity_note_actions` (tasks) |
| table `invoice_e_deliveries`                                          | `e_invoice_deliveries`                                        |
| hint codes `EINVOICE_*`                                               | `E_INVOICE_*`                                                 |

Run `better-supabase upgrade` to rename the table and to copy stored action items into tasks
(the `tasks` block must be installed). Old operation action names in delegated tokens still
resolve. `parseScaled` is exported from `commerce/money` and shared with the audit file readers.
Every block manifest takes a `description`, which the block catalog reads. ADR 0206 records
`invoice_e_endpoints` as the one naming exception.
