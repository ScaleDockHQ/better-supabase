---
"better-supabase": minor
---

`EntitySurface.offline` takes a `join` list (`EntityOfflineJoin`) that declares the tables and rules the PowerSync streams join to the entity's rows: the notification events and preferences, the membership role sets and organizations, and the attachment reader and subject rules. `better-supabase powersync streams` reads them from the manifests, and the generated YAML does not change. The manifest contract stays at `apiVersion` 1, and `EntityOfflineJoin` and `EntityOfflineJoinTable` are exported from `better-supabase/blocks`.
