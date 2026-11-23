---
"better-supabase": minor
---

The authorizer's request context gains `enforcement: "rls" | "definer"`. Repository `create`, `update`, `delete` and `upsert` through a caller's db send `rls`, because RLS checks the write again; an admin db never does. Block verbs send `definer`. Actions, routes, resource actions and MCP tools take `enforcement` on their definition and send nothing by default, which a provider treats as `definer`. `recordingAuthorizer` in `better-supabase/testing` records each check's operation, intent and enforcement, and `testAuthorizer` checks that `enforcement: "rls"` never turns a denial into a grant. Additive on `apiVersion: 1`. See ADR 1221.
