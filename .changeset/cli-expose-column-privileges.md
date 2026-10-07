---
"better-supabase": patch
---

The CLI accepts column privileges in `expose`. Its config validator allowed only `select`, `insert`, `update` and `delete`, so a config with `"update(username, first_name)"` failed with `expose.profiles: Invalid type` although the `ExposePrivilege` type and the JSON Schema accept it. It now checks each privilege with the same pattern `resolveConfig` uses.
