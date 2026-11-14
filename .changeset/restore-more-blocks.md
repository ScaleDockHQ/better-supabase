---
"better-supabase": minor
---

`cases`, `lims`, `contacts`, `consents`, `shifts` and `observations` get a
restore next to their archive. Each needs the permission its archive needs,
and restoring an entity that is not archived changes nothing.

| Block          | New method                                | New event                             |
| -------------- | ----------------------------------------- | ------------------------------------- |
| `cases`        | `restoreKind(kindId)`                     | `case_kind.restored`                  |
| `lims`         | `restoreMethod(methodId)`                 | `lims_method.restored`                |
| `contacts`     | `restoreCompany(id)`, `restorePerson(id)` | `company.restored`, `person.restored` |
| `consents`     | `restorePurpose(purposeId)`               | `consent_purpose.updated`             |
| `shifts`       | `restoreTemplate(templateId)`             | none                                  |
| `observations` | `restoreDefinition(definitionId)`         | `observation_definition.updated`      |

`archiveCompany` and `archivePerson` with `archived: false` now record the
restored event too. Run `better-supabase upgrade` and apply the migration.
