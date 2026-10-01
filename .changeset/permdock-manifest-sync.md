---
"better-supabase": minor
---

Doctor and `gen` read PermDock's `permdock.manifest.json` and `permissions.catalog.json` (paths set by `permdock.manifest` and `permdock.catalog` in the config). BS407 recognizes PermDock's hook by the manifest or its `-- permdock:hook v1` marker, treats functions in `supabase.hook.claims` as the hook's own sources, flags a wrapper that writes those claims again, and reports an info finding when `permdock.config.ts` has no manifest. BS405 takes PermDock's budget from the manifest. The new BS214 reports bucket and topic policies that pass a permission with `rowConditions: true` to PermDock's helpers, `gen` refuses to write such bucket policies, and `defineBucket` and `defineTopic` throw for those keys when given the catalog as `catalog`. The MCP recipe narrows `tool.meta` with PermDock's `isPermission` before `can` and `mayUse`.
