---
"better-supabase": minor
---

Resume an `approval-required` decision. `approval: { header: "x-approval-id" }` on the server options names the header the client sends the approval id in; it reaches `ctx.approval` and the authorizer's `context.approval`, never the subject. MCP reads it from the header or `params._meta.approval`, returns the id in `structuredContent.approval`, and keeps tools that need an approval in `tools/list`.
