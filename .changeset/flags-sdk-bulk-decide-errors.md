---
"better-supabase": patch
---

`bulkDecide` on the Flags SDK adapter no longer answers `{}` when the flag definitions fail to load. It now answers each flag's `defaultValue`, and throws with the load error for a flag that has none, as `decide` does, so `evaluate([...])` reports an outage instead of serving no value. The Flags SDK docs show `mergeProviderData` for a project that uses this adapter next to Vercel Flags, and the chat UI recipes add a `chat-message-markdown` recipe that renders answers with Streamdown.
