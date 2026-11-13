---
"better-supabase": patch
---

Offline attachments no longer break signed uploads. Storage checks upload permission by inserting a trial `storage.objects` row and rolling it back, and that row carries the request's own content type and no size. The `attachment_object_uploaded` trigger now fires only on objects with a size, so `createSignedUploadUrl` for a pending attachment stops failing with check violation 23514 on the mime type. Run `better-supabase upgrade` and `db diff` to pick up the new trigger.
