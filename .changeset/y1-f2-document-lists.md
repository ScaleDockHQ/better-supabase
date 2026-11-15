---
"better-supabase": minor
---

Pages the inventory, drive, qualifications, versions, attachments, signatures,
templates and forms blocks by the block list contract (ADR 1077). Each gains
`page`, `facets` and `count` methods with `q`, sorts and list filters:
`inventory.levelPage`, `movementPage` and `lotPage` (with `getLevel`,
`getMovement` and `getLot`), `drive.documentPage` and `getDocument`,
`qualifications.typePage` and `getType`, `versions.versionPage`,
`attachments.attachmentPage`, `signatures.requestPage`,
`templates.templatePage` and `getTemplate`, and `forms.submissionPage`. The SQL
adds `page_inventory_levels`, `page_inventory_movements`, `page_inventory_lots`,
the three `get_inventory_*` reads, `page_drive_documents`,
`page_qualification_types`, `get_qualification_type`, `page_versions`,
`page_attachments`, `page_signature_requests`, `page_templates` and
`page_form_submissions`, and `list_forms` gains search. The generated schema
files need `better-supabase upgrade`. The array methods keep working and are
deprecated.

| Old                     | New                          |
| ----------------------- | ---------------------------- |
| `inventory.levels`      | `inventory.levelPage`        |
| `inventory.movements`   | `inventory.movementPage`     |
| `drive.documents`       | `drive.documentPage`         |
| `qualifications.types`  | `qualifications.typePage`    |
| `versions.list`         | `versions.versionPage`       |
| `attachments.list`      | `attachments.attachmentPage` |
| `signatures.list`       | `signatures.requestPage`     |
| `templates.list`        | `templates.templatePage`     |
| `forms.listSubmissions` | `forms.submissionPage`       |
