---
"better-supabase": minor
---

Record the SHA-256 of file bytes. Attachments (module version 9) get `sha256` and `hash_verified_at`, set by the scanner from the file it downloaded. Versions (module version 2) get `file_hash` and `hash_version`, and `snapshot` takes `fileSha256` from the service role. `set_attachment_status`, `version_insert` and `snapshot_version` take one more trailing argument, and the old signatures are dropped.
