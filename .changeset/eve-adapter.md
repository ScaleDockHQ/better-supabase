---
"better-supabase": minor
---

Adds `better-supabase/eve`, which runs eve agents on Supabase (Node only, `eve` is an optional peer). `supabaseAuth` verifies the Supabase session on eve routes and maps the user to an eve principal. `credentialAuth` gives MCP connections their tokens from a credential provider such as Vault or Vercel Connect, with eve's authorization flow when the provider has one. `supabaseMemory` is a memory provider over the memory and knowledge blocks, and `supabaseDocumentBackend` stores eve's file memory in Postgres. `persistSessions` copies eve sessions into the AI chat tables, and `routeInbox` hands inbox conversations in bot mode to eve's Chat SDK channel. The `memory` SQL module adds `memory_documents`, versioned documents under a scope key, exposed as `memory.documents`.
