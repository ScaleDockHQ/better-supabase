---
"better-supabase": patch
---

Document and test contract-first oRPC routers: `bs.middleware()` applies to `implement(contract)`, and `bs.fetchHandler` serves an `OpenAPIHandler` under Hono with RLS denials answering 403 and missing rows 404.
