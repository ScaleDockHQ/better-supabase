---
"better-supabase": patch
---

With `blocks.sessions.options.authzVersions`, deleting an auth user who belongs to an organization no longer fails on `user_authz_versions_user_id_fkey`. The membership's cascade delete bumped the version of the user being deleted; `bump_authz_versions` now skips users that no longer exist. Run `upgrade` and write the migration.
