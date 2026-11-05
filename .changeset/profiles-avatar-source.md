---
"better-supabase": minor
---

Adds `blocks.profiles.options.avatarSource`. With `"path"`, the author that `message_authors` and `attachment_authors` return carries `avatarPath` (the Storage path from the profiles `avatar_path` column) and a null `avatarUrl`, so an app that stores avatars in Storage can build the URL itself. The default `"url"` is unchanged. `Author` gains an optional `avatarPath`.
