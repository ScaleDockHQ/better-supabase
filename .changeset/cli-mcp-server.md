---
"better-supabase": minor
---

Add `better-supabase mcp`, which serves the CLI to a coding agent as an MCP server on stdio. The read-only tools (`doctor`, `blocks_list`, `config`, `gen_check`, `apply_dry_run` and others) run by default, and `--allow-writes` adds `gen`, `sql_sync`, `apply` and `add`, each of which asks for the user's consent with a token before it writes. `better-supabase/mcp` now exports `answerMessage` and `answerLine` for serving a `ProtocolServer` over any transport, and `createMcp` logs one warning naming the tools a missing authorizer hides.
