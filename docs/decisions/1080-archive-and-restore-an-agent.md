# 1080: Archive and restore an agent (lane Y2, slice 9)

- Status: accepted
- Date: 2026-11-15
- Amends: 1052

## Context

ADR 1052 gives the agent an archive. `delete_agent` removes the agent with its
installs, ratings and skills, so an owner who retires a published agent also
takes it away from everyone who installed it, and the only way to hide it is to
make it private, which loses what it was published as.

## Decision

`archive_agent` and `restore_agent` follow the delete rule: the owner or a
member with the moderate key. They record `agent.archived` and `agent.restored`
once, and archiving an archived agent, or restoring one that is not archived,
returns it unchanged.

- The agents table gains an optional `archived_at` column, and the agent JSON
  carries `archived_at`.
- `list_agents` hides archived agents in every filter by default and takes
  `include_archived` as a last argument, so the migration drops the four
  argument form. `get_agent` still reads one by id.
- `save_agent`, `publish_agent`, `set_agent_skills`, `rate_agent` and
  `install_agent` refuse an archived agent with `AGENT_ARCHIVED` (SQLSTATE
  55000). Uninstalling stays possible. Restoring keeps the visibility the
  agent had.
- `delete_agent` becomes `purge_agent` and `agent.deleted` becomes
  `agent.purged`. Purging needs `permissions.purge`, falling back to the
  moderate key, for the owner too, because it removes other members' installs
  and ratings (ADR 0851).

## Consequences

Breaking for callers of `agents.remove`, for sinks that match `agent.deleted`
and for owners who purged their own agent without the moderate key; the
changeset and the 0.66 to 0.67 guide have the old-to-new table. A custom agents
table without `archivedAt` gets neither function and keeps the four argument
list.
