---
"better-supabase": minor
---

The attachments and drive blocks keep their bytes in a versioned `FileStore` (`put`, `get`, `delete`, `signedUrl`, with optional `head` and `signedUploadUrl`) from `better-supabase/storage`. `supabaseFileStore(storage)` is the default, so nothing changes without the new `files` option; `vercelBlobStore(blob)` stores the files in Vercel Blob, with `@vercel/blob` as an optional peer. Postgres still decides who may upload: `confirm_attachment` takes an optional `object` (`{ size, mimetype }`) that only the service role may pass, checked against the bucket's limits, so pass `service` to `createAttachments` and `createDrive` with an external store. Image transforms, public URLs and the upload claim stay Supabase-only (`ATTACHMENT_STORE_UNSUPPORTED`). Run `better-supabase upgrade` (attachments module 9 to 10) and apply the new migration. `testFileStore` in `better-supabase/testing` checks your own store.

| Before                                    | After                                                                  |
| ----------------------------------------- | ---------------------------------------------------------------------- |
| `confirm_attachment(id uuid)`             | `confirm_attachment(id uuid, object jsonb default null)`               |
| `storage` required on `createAttachments` | `storage` or `files`; `files` defaults to `supabaseFileStore(storage)` |
