---
"better-supabase": minor
---

Every action a module checks is an operation named `<module>.<action>`, and `better_supabase.operation_permission(op)` returns its permission key in SQL, after `sql.modules.<module>.permissions` renames and with the provider's `operations` over them. MCP tools take an optional `operation`, agents take `toolOperations`, and workflow-builder step library entries take `operation`, each naming the entry to check in place of `mcp.tool.<name>`, `ai.tool.<name>` or `workflow.run`.
