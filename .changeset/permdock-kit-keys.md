---
"better-supabase": patch
---

Under the `permdock` access model, `better-supabase sql add` and doctor (BS411) check every permission key the kit modules check against `permissions.catalog.json`, platform keys for `permdock_has` included. A key must be `rowConditions: false`, because PermDock's helpers check role and scope only; a key with row conditions, without the flag or missing from the catalog stops `sql add`. `kitPermissionKeys(kits, names)` from `better-supabase/sql` lists the keys with their module, action and scope, and `kitFilePaths(names, layout)` lists the files a set of modules writes without rendering them, so `sql list` works while the access settings are incomplete.
