---
"better-supabase": minor
---

`teams` and `organizations` follow the block list contract (ADR 1077).
`teams` gains `teamPage`, `teamFacets`, `teamCount` and `getTeam`, with `q`
over the name, slug and description and a `status` filter list.
`organizations` gains `membersPage`, `membersFacets` and `membersCount`, sorted
by `role` or `userId` and filtered by `role`. `teams.list` stays as a
deprecated alias until 0.70.
