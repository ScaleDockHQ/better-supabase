---
"better-supabase": patch
---

`attachments.upload` and `attachments.put` delete the record they created when Storage refuses the signed upload URL or the upload, such as a bucket policy or the read-only Storage of a support session, and return the refusal. Before, the record stayed `pending` with no object behind it.
