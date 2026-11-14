---
"better-supabase": minor
---

Breaking: the hard delete of a team is `purge`, behind its own
`permissions.purge` key. Archive and restore stay.

| Before                            | After                            |
| --------------------------------- | -------------------------------- |
| `teams.delete(id)`                | `teams.purge(id)`                |
| `delete_team(team)` (SQL)         | `purge_team(team)`               |
| event `team.deleted`              | event `team.purged`              |
| `blocks.teams.permissions.delete` | `blocks.teams.permissions.purge` |
| `TeamWrites.delete` (PowerSync)   | `TeamWrites.purge`               |

Run `better-supabase upgrade` and apply the migration. Purging falls back to
the `manage` key until you set `permissions.purge`. See the 0.66 to 0.67
guide.
