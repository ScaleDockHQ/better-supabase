# 1026: Restore for the remaining archive blocks (slice 4b)

- Status: accepted
- Date: 2026-11-14

## Context

ADR 0839 pairs every `archive` with a `restore`; ADR 1025 covered cases, lims,
contacts, consents, shifts and observations. Assets, medications, compliance,
content, option-sets and pipelines still archived without a way back.

## Decision

Each block gets a restore with the permission its archive needs. Restoring an
entity that is not archived changes nothing.

| Block         | New client method         | New event                                              |
| ------------- | ------------------------- | ------------------------------------------------------ |
| `assets`      | `restoreLocation`         | `asset_location.restored`                              |
| `medications` | `restoreMedication`       | none (the catalog records no events)                   |
| `compliance`  | `restorePolicy`           | none; the every-member assignment is placed again      |
| `content`     | `restore`                 | `content_entry.restored`; the entry returns as a draft |
| `option-sets` | `restoreItem`             | `option_set_item.restored`                             |
| `pipelines`   | `restore`, `restoreStage` | `pipeline.restored`, `pipeline_stage.restored`         |

A restored location needs an active parent, and a restored stage needs an
active pipeline. A restored pipeline is not the default again. Records that
an archive moved to a replacement stay there.

## Deferred

`care-plans` archive ends the plan's open actions, which a restore cannot
bring back, so what a restored plan means (a draft with no actions) needs a
product decision. Invoices, risks, shipments and bookings have no archive
method yet, only an `archived_at` column mapping, so they need an archive
first.

## Consequences

Each new SQL function adds security-definer functions to the practices
baseline.
