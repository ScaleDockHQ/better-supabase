---
"better-supabase": minor
---

The inbox no longer owns `inbox_teams` and `inbox_team_members`. It requires the `teams` block and assigns a conversation to a `teams` row. Installing both copies the old rows and drops the old tables. `create_inbox_team` and `set_inbox_team_member` call the teams functions. Team ids stay `uuid` while the inbox is installed.
