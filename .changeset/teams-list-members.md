---
"better-supabase": minor
---

`teams.list()` returns each team's `description`, `status` (`active` or `archived`) and `memberIds`, sorted by name, so an app can tell archived teams apart and show who is on a team without reading `team_members` itself. `teams.update()` returns the stored row, including a description it kept. Run `better-supabase upgrade` and generate a migration to pick up the new `list_teams` and `update_team`.
