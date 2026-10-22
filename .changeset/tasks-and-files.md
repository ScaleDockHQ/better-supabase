---
"better-supabase": minor
---

Attachments keep versions and show image previews, and work items get checklists, repeat rules, watchers and attachments. See [Attachments](https://bettersupabase.com/docs/blocks/attachments) and [Work items](https://bettersupabase.com/docs/blocks/work-items).

Run `better-supabase sql upgrade` (or `sql sync` and a new migration): `create_attachment` takes three more arguments, so the upgrade drops and recreates it.

- `attachments.replace(id, file)` uploads a new file under the same attachment and keeps the current one as an earlier version. `versions(id)` lists them and `restore(id, version)` makes one current again. Both emit `attachment.replaced` and `attachment.restored`.
- Attachments record `width`, `height` and `pages`, and `attachments.images(options)` signs resized URLs for `useImage`, behind the scan gate.
- `createAttachmentUploadController` and `useAttachmentUpload` in `better-supabase/blocks/attachments/react`, `/vue`, `/svelte` and `/solid` upload files side by side with progress, wait for the scan, and retry or dismiss a failed upload.
- Work items take `attachmentIds` on `create` and an `attachments` change on `update`, which link files the caller uploaded without a subject.
- Work items have checklists: `saveChecklistItem`, `removeChecklistItem` and `checklist`, and each item carries `checklist: { total, done }`. `get(id)` reads one item. The `checklist` section (`workItemChecklistSection`, with the `workItemChecklistOptimistic` reducer) shows the steps on the item's page.
- With the reminders block installed, `setRecurrence(id, { rrule, tzid })` gives an item a repeat rule, and `workItemRecurrenceSink(workItems)` creates the next item when a repeating one is completed. `repeat(id, dueAt)` runs once per item, so a redelivered event changes nothing.
- With the notifications block installed, `watch(id, level)` and `watchers(id)` follow an item through notification subscriptions.
