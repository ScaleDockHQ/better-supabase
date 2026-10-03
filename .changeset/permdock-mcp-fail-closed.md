---
"better-supabase": patch
---

The PermDock MCP recipe in the docs and the auth skill fails closed: a tool without a PermDock permission in `meta` is hidden (`visible` returns `false`) and refused (`authorize` returns `{ allowed: false }`). The page also shows PermDock's `decide` for putting the denial reason in the refusal.
