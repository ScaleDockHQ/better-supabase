---
'better-supabase': minor
---

`createMcp` takes optional per-tool authorization hooks. `authorize(ctx, tool, args)` runs after the arguments are validated and before `run`, and returns `{ allowed: true }` or `{ allowed: false, reason?, scopes? }`. A refusal is a tool error, and a refusal with `scopes` is a 403 `insufficient_scope` challenge that lists the scopes the call needs. `visible(ctx, tool)` filters `tools/list`, and a hidden tool is called like an unknown one. `defineTool` and `mcp.tool` accept an opaque `meta`, for example a PermDock permission, which both hooks receive and clients never see. New types: `ToolRef` and `ToolDecision`. The PermDock guide has a recipe that checks PermDock permissions through a structural type.
