# 0243: Option sets, lane archiving with a move target and brand starters

- Status: accepted
- Date: 2026-11-05

## Context

Apps that serve several customers need board lanes and field choices (priority,
severity) that a customer can rename, add, reorder and remove, and starter
wording that differs per brand. Pipelines already had tenant-editable stages,
but removing a stage that held records was refused with no way to move them, a
stage had no icon, and a new organization always started from one template.
Priority was a fixed smallint with labels in app code.

## Decision

A new `option-sets` block keeps `option_sets` and `option_set_items`. A binding
`on.<type>.<field>` names a level range, a level column and an option column
(`<column>_option_id`). A trigger writes the chosen item's level to the level
column, so queries keep sorting on a number. `archive_option_set_item(item,
replacement)` moves the records that use the item and writes the replacement's
level; without a replacement an item in use is refused. The `tasks` block
contributes a `priority` binding with five items at levels 0 to 4.

Pipelines gain two things. `archive_pipeline_stage(stage, move_to)` moves the
records to another active stage of the same pipeline before it archives the
stage. The move sets a transaction-local setting that the stage trigger reads to
skip the allowed-transitions check for that pair: transitions guide people, they
do not restrict an administrator who removes a lane. Stages also take an `icon`.

Both blocks accept `options.brand` (`{ table, column, tenant? }`) and a `brands`
map on a binding. The brand is read once, when the default set or pipeline is
created on first use, through the shared `brandSourceOf`. A pipeline binding with
`brands` is created on first use instead of through `pipelines.seeds`, because a
seed row cannot depend on a column of the organization.

`option-sets` sits before `ensure_rls` in the module registry, so the generated
file number of `rls-guard` moves from 183 to 184.

## Alternatives considered

- A priority enum per app. Customers could not rename or extend it.
- Storing only the item id and joining for the level. Every sort and filter
  would need the join, and existing `priority` columns would break.
- Seeding brand stages through `pipelines.seeds`. Seeds are plain rows and
  cannot branch on the organization.

## Consequences

An existing install gains the `icon` column through an `alter table ... add
column if not exists` and the new `save_pipeline_stage` and
`archive_pipeline_stage` signatures (the old ones are dropped). Changing an
organization's brand later does not rename stages or items that exist.
