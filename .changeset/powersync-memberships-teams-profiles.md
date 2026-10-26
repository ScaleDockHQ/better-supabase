---
"better-supabase": minor
---

`better-supabase powersync streams` accepts the `memberships`, `teams` and `profiles` instances. Memberships syncs the user's own memberships and the organizations they belong to, teams syncs the user's teams and their members, and profiles syncs the user's own profile. `better-supabase/powersync` adds `powersyncMembershipsTransport`, `powersyncTeamsTransport` and `powersyncProfilesTransport`, which answer the list and update functions from SQLite, and `membershipsRoute`, `teamsRoute`, `teamMembersRoute` and `profilesRoute` for `createUploadConnector({ tables })`, which replay local writes through the block functions.
