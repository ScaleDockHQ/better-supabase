---
"better-supabase": patch
---

Security fix for support session upload claims. In 0.12.0, `claimSignedUpload`, `claimReserved` and the blocks' `confirm` and `commit` claimed any object without an owner on a path the target may insert into. That could include a file the service role stored earlier, such as an export or an import, which the claim then handed to the target and stamped with the session. A claim now only takes an object without an owner whose `updated_at` is at or after the session's `startedAt`, and in a versioned bucket only the current version. Older objects are refused with `403` `AccessDenied`. An upsert reservation that replaces such an object during the session can still be claimed.

`SupportStorageOptions.session` now needs `startedAt`. The server already passes the whole `SupportSession`; pass it too when you call `supportStorage` yourself. `uploadToSignedUrl` on the server and `upload` with `onProgress` now remove the object when the claim fails or is refused, not only when it throws. The impersonation page documents the limits of the claim's insert rehearsal and how to sweep uploads that are never claimed.
