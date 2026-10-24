---
"better-supabase": minor
---

A block that runs over one of your tables names its policies there `bsb_<table>_<command>` (such as `bsb_teams_select`) and prefixes its triggers with `bsb_`, so they never replace a policy or trigger of yours with the same name. When your table already keeps `updated_at` current with its own trigger, the block adds no `bsb_updated_at` trigger there.

Doctor reports both. BS347 (warning) names a block policy on your table for a command you have your own policies for, when none of them repeats its condition, since Postgres ORs permissive policies and the block's can open rows yours keep closed; a command you have no policy for is the block's to grant. BS348 (info) names a table whose own `updated_at` trigger the block keeps.

| Before                                                       | After                      |
| ------------------------------------------------------------ | -------------------------- |
| `teams_read` on an app-owned `teams` table                   | `bsb_teams_select`         |
| `team_members_read` on an app-owned `team_members` table     | `bsb_team_members_select`  |
| `bsb_organizations_read` on an app-owned organizations table | `bsb_organizations_select` |
