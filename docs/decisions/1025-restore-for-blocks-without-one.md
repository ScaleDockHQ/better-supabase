# 1025: Restore for blocks without one (slice 4a)

- Status: accepted
- Date: 2026-11-14

## Context

ADR 0839 pairs every `archive` with a `restore`. Cases, lims, contacts,
consents, shifts and observations archive an entity but give no way back
except an upsert that clears the flag by hand.

## Decision

Each block gets a restore next to its archive, needing the same permission.
Restoring an entity that is not archived changes nothing and records nothing.

| Block          | New client method                 | New event                             |
| -------------- | --------------------------------- | ------------------------------------- |
| `cases`        | `restoreKind`                     | `case_kind.restored`                  |
| `lims`         | `restoreMethod`                   | `lims_method.restored`                |
| `contacts`     | `restoreCompany`, `restorePerson` | `company.restored`, `person.restored` |
| `consents`     | `restorePurpose`                  | `consent_purpose.updated` (restored)  |
| `shifts`       | `restoreTemplate`                 | none (templates record no events)     |
| `observations` | `restoreDefinition`               | `observation_definition.updated`      |

Contacts reuse `archive_company` and `archive_person` with `archived: false`,
which now record the restored event. The other blocks get a `restore_*` SQL
function. Consents and observations record their existing `updated` event
because their archive does too.

## Consequences

Each new SQL function adds security-definer functions to the practices
baseline. The blocks still without a restore (assets, medications, compliance,
content, care-plans, pipelines, option-sets) follow in slice 4b.
