---
"better-supabase": patch
---

Security: with `sql.modules.attachments.options.subjects`, the storage read policy on `storage.objects` now checks the attachment's subject. Before, a tenant member with `attachments.read` (or the uploader, or `attachments.manage`) could read the object of an attachment whose subject row they cannot see, even though the attachment row itself was hidden. The policy now also requires the row to be visible through the table's own read policy (`attachment_object_visible`). Run `better-supabase sql sync` and ship the migration.
