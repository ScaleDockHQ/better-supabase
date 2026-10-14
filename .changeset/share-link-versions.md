---
"better-supabase": minor
---

`create_share_link` takes a `version_id` that pins the link to a version of its subject and must belong to it, and `shareLinks.create(..., { versionId })` passes it. `shareLinks.resolve(token)` is typed and returns `versionId`. The `versions` module adds `get_shared_version`, granted to anon, and the client gains `versions.getShared(token)`, which reads a pinned version through its link.
