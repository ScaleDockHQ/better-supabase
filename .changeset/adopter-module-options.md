---
"better-supabase": minor
---

More module settings for apps that adopt existing tables: an `invitation_preview_extra(invitation)` hook merges app keys into `invitation_preview`; `sql.modules.organizations.permissions.updatePlatform` and `deletePlatform` let platform staff edit or delete any organization; `sql.modules.profiles.options.usernameFrom` joins several metadata keys (`{ names, separator }`) and `readPolicy: { members, platform }` lets platform staff read every profile; `sql.modules.reserved-slugs.options.slugs` adds the app's own reserved words. `modulePermissionKeys` lists the optional organization platform keys a config names.
