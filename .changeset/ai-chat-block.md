---
"better-supabase": minor
---

The `ai-chat` SQL module and `createAiChat` in `better-supabase/blocks/ai-chat` store AI conversations: chats and projects per user and tenant, a branching message tree in the canonical message format, runs with a compare-and-set stream claim, tool approvals and policies, pending inputs, feedback, hashed share links, a model catalog per plan and moderation events. `better-supabase/blocks/ai-chat/react` adds `useAiChats`, `useAiChatTree`, `useAiModels` and `useAiShare`.

`better-supabase/ai-sdk` connects the AI SDK to the block, with `ai` and `@ai-sdk/react` as new optional peers: message converters (`fromUIMessage`, `toUIMessages`), AI Gateway helpers (`gatewayOptions`, `usageOf`, `usageQuota`) and the `costBackfill` and `modelCatalogRefresh` job handlers. `createAssistant` in `better-supabase/ai-sdk/chat` serves a resumable chat route with stop, model checks, moderation and quotas, and `useAssistant` in `better-supabase/ai-sdk/react` is `useChat` wired to it. The UI message stream protocol is pinned as `SPEC_PINS.aiSdkUiMessageStream`.
