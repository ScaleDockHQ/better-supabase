---
"better-supabase": minor
---

Breaking: `agents` gets `archive` and `restore`, and the hard delete of an agent
is `purge`, behind its own `permissions.purge` key (it falls back to
`agents.moderate`, and the owner needs it too). An archived agent leaves the
store and `list`, and `update`, `publish`, `install` and `rate` refuse it with
`AGENT_ARCHIVED`; its installs, ratings and skills stay. `list` takes
`includeArchived`, and `Agent` carries `archivedAt`.

| Before                    | After                                |
| ------------------------- | ------------------------------------ |
| `agents.remove(id)`       | `agents.purge(id)`                   |
| `delete_agent(id)`        | `purge_agent(id)`                    |
| event `agent.deleted`     | event `agent.purged`                 |
| `list_agents` with 4 args | a fifth argument, `include_archived` |

New events are `agent.archived` and `agent.restored`. Run `better-supabase
upgrade` and apply the migration. See the 0.66 to 0.67 guide.
