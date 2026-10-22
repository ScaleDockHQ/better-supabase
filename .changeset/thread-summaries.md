---
"better-supabase": minor
---

Add AI thread summaries to the messaging block, without tying it to an SDK.

- `messaging.summarize(target, summarizer, { force, maxMessages })` summarizes a conversation (`{ conversationId }`) or a thread (`{ threadId }`) from the messages the caller can read, leaving out internal notes and deleted messages, and saves it as the service role. `messaging.summary(target)` reads it. A saved summary is `stale` once a message in its scope is sent after it, edited or deleted, and `summarize` returns a current one without calling the model.
- The summarizer is a versioned `ThreadSummarizer` (`apiVersion: 1`). `summarizeWith(model, { providers, instructions, gateway, maxOutputTokens })` from `better-supabase/ai-sdk` provides one over `generateText` with an AI Gateway model string, tags the spend with the tenant and the `summary` feature, and sends the tenant's own keys as BYOK when you pass the ai-providers block.
- `createMessaging` takes an optional `service` transport for the summary writes; `createBlocks` passes it.

Run `better-supabase sql sync` and generate a migration to get the `thread_summaries` table and the `thread_summary` and `save_thread_summary` functions.
