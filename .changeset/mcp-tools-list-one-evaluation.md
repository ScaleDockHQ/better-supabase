---
"better-supabase": minor
---

MCP `tools/list` decides every tool in one `evaluations` call when the authorizer has it, instead of one call per distinct permission. A list of 300 tools with 300 permissions makes 1 call instead of 300. `outcomesOfMany` in `better-supabase/core` is the helper behind it. An authorizer without `evaluations` is called once per tool as before, so nothing changes for it. `upgrade` rewrites no module and no data migration is needed.
