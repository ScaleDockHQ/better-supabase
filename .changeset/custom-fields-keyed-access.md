---
"better-supabase": minor
---

The custom-fields keyed layout takes `options.rankType: "integer"`, which keeps `rank` in an integer column (or casts it to the type of the app's own rank column), and `options.readAccess: "record"`, which makes `read_field_values` check each record through `can_subject(type, id, 'read')` instead of `permissions.read` in the tenant. The keyed layout no longer reports `permissions.sensitive` to the authorization provider, since it keeps no sensitive values. A module can now name the actions a config never checks with `unusedPermissions`.
