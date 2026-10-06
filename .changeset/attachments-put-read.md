---
"better-supabase": minor
---

`attachments.put(attachment, file)` creates the record, uploads the bytes from the server and confirms it in one call, and `attachments.read(id)` returns a file's bytes as a `Blob` behind the same scan gate as `download`. `AttachmentBucket` gains the optional `upload` that `put` uses, which `supabase.storage.from(bucket)` has.
