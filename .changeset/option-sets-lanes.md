---
"better-supabase": minor
---

New `option-sets` block (`better-supabase/blocks/option-sets`), lane archiving with a move target, stage icons and brand starters.

- `option-sets` keeps tenant-editable items for a field such as priority. A binding `on.<type>.<field>` adds an option column to the record and writes the chosen item's level to the field's number column. `archiveItem({ itemId, replacementId })` moves the records that use the item. `createOptionSetsController` wraps the client for a settings screen. The permission keys are `option-sets.read` and `option-sets.manage`.
- `tasks` contributes a `priority` binding with the items None, Low, Medium, High and Urgent at levels 0 to 4, and adds `priority_option_id`.
- `pipelines.archiveStage` takes `{ stageId, moveTo }`. Records in the stage move to `moveTo` before it is archived, and the allowed stage changes do not apply to that move. `archive_pipeline_stage` now has two arguments and `save_pipeline_stage` takes an `icon`. Stages, board columns and stage templates carry an optional `icon`.
- `blocks.pipelines.options.brand` and `blocks.option-sets.options.brand`, with a `brands` map on a binding, start an organization of that brand with its own stages or items.

Run `better-supabase add option-sets` and generate a migration. `archiveStage(stageId)` is now `archiveStage({ stageId })`.
