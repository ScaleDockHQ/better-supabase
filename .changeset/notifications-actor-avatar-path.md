---
"better-supabase": minor
---

Profiles get an `avatarPath` column (`avatar_path` on a managed table) for an avatar stored in Storage. Sync never writes it from auth metadata, users can update it, and a `metadata` option that names it is refused; an adopted table gains it only when `columns.profiles.avatarPath` maps it. `notifications.list({ include: ["actor"] })` returns the actor's `avatarPath`, and the new `avatars` option (`{ url, bucket }` or a function of the path) adds `actor.avatarUrl`.
