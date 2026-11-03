---
"better-supabase": patch
---

Tested against ai 7.0.159, @ai-sdk/react 4.0.163 and @ai-sdk/workflow 2.0.91. Adds `@chat-adapter/catalog` (`>=4.43 <5`) as an optional peer for the chat-sdk helpers that read the adapter catalog. Install it only if you use them. The peer ranges for the AI SDK packages are unchanged.
