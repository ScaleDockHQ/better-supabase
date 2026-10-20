---
"better-supabase": minor
---

Signed uploads work in a writable support session. `supportStorage` used to refuse `createSignedUploadUrl` and `uploadToSignedUrl` with `SUPPORT_STORAGE_WRITES`, so `bucket.connect(storage).reserve(...)` and the blocks' browser uploads failed, and an admin could not upload a file as the user. Now `createSignedUploadUrl` runs the same dry run as `upload` as the target (an insert, or an upsert with `upsert: true`, refused with Storage's `403`), then the service client signs the URL.

An object uploaded to a signed URL has no owner, so a claim step finishes the upload. It checks again that the target may insert at the path, then makes the target the owner and adds `supportSessionId` and `supportAdminId` to the object's `user_metadata`. It claims only an object without an owner; one another user owns is refused with `403` `AccessDenied`. The `StorageApi` that `supportStorage` returns has `claimSignedUpload(bucket, path)`, and a connected bucket has `claimReserved(reservation)`, which succeeds without a request outside a support session, so call it after a reserved upload and before you record the file. `uploadToSignedUrl` on the server and `upload` with `onProgress` claim on their own.

The blocks claim in their own finish step: `attachments.confirm`, `drive.commit` and the AI files block's `files.confirm` claim the upload before they record it. A refused claim keeps the record pending and returns the block's `forbidden` (`ATTACHMENT_FORBIDDEN`, `DRIVE_FORBIDDEN`, `AI_FILE_FORBIDDEN`) or `not_found` (`ATTACHMENT_NOT_UPLOADED`, `AI_FILE_NOT_UPLOADED`) error. Outside a support session they make no extra request. Read-only sessions still refuse every write with `SUPPORT_READ_ONLY`.
