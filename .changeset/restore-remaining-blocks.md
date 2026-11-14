---
"better-supabase": minor
---

`assets`, `medications`, `compliance`, `content`, `option-sets` and `pipelines`
get a restore next to their archive. Each needs the permission its archive
needs, and restoring an entity that is not archived changes nothing.

| Block         | New method                         | New event                                      |
| ------------- | ---------------------------------- | ---------------------------------------------- |
| `assets`      | `restoreLocation(locationId)`      | `asset_location.restored`                      |
| `medications` | `restoreMedication(medicationId)`  | none                                           |
| `compliance`  | `restorePolicy(policyId)`          | none                                           |
| `content`     | `restore(entryId)` (back as draft) | `content_entry.restored`                       |
| `option-sets` | `restoreItem(itemId)`              | `option_set_item.restored`                     |
| `pipelines`   | `restore(id)`, `restoreStage(id)`  | `pipeline.restored`, `pipeline_stage.restored` |

Run `better-supabase upgrade` and apply the migration.
