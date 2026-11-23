---
"better-supabase": minor
---

The tasks block can treat MCP clients and API keys as agents, approve each hold kind under its own policy, and list the tasks that wait on a prerequisite:

- `options.claims.agents` lists the session kinds the claim rules treat as agents: `"agent"` (always), `"oauth-client"` (a token with `client_id`, or an `act` claim without a kind) and `"api-key"`. Such a session claims only tasks assigned to its user and can't take over a reserved task.
- `options.hold.approval.kinds` also takes a record from hold kind to `true` or `{ policy, onReject }`. Each kind files under its own policy and settles a rejection its own way; a field left out comes from the block-wide option.
- The `waiting` list filter returns open tasks whose `waiting_on` count is above zero.

The module moves to version 8; re-run `better-supabase add` to update the SQL. The upgrade adds no statement to an existing install.
