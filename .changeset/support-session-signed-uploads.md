---
"better-supabase": minor
---

Signed uploads work in a writable support session. `supportStorage` used to refuse `createSignedUploadUrl` and `uploadToSignedUrl` with `SUPPORT_STORAGE_WRITES`, so `bucket.connect(storage).reserve(...)` failed and an admin could not upload a file from the browser as the user. Now `createSignedUploadUrl` runs the same dry run as `upload` as the target (an insert, or an upsert with `upsert: true`, refused with Storage's `403`), then the service client signs the URL.

An object uploaded to a signed URL has no owner, so the new claim step finishes the upload: `claimReserved(reservation)` on a connected bucket, or `claimSignedUpload(path)` on the `StorageApi` that `supportStorage` returns. It checks again that the target may insert at the path, then makes the target the owner and adds `supportSessionId` and `supportAdminId` to the object's `user_metadata`. It claims only an object without an owner; one another user owns is refused with `403` `AccessDenied`. Outside a support session `claimReserved` succeeds without a request, so call it after every reserved upload, before you record the file. `uploadToSignedUrl` on the server and `upload` with `onProgress` claim on their own. Read-only sessions still refuse every write with `SUPPORT_READ_ONLY`.
