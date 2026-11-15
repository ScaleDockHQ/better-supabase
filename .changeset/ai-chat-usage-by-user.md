---
"better-supabase": minor
---

`ai-chat` gains `runs.usageByUser({ organizationId, since?, until?, limit? })`,
which returns runs, failed runs, tokens and cost per user across an
organization, most expensive first. `ai_runs` stays readable by its owner only;
the read needs `ai_chat.manage` in the organization (or the service role) and
fails with `AI_CHAT_FORBIDDEN` otherwise. It is backed by the new
`ai_usage_by_user` SQL function, which `better-supabase upgrade` writes into the
module: run it and apply the migration it generates.
