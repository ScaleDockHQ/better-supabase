---
"better-supabase": minor
---

The `ai-chat` and `ai-files` SQL modules store AI conversations and their files, and `better-supabase/ai-sdk` connects them to the AI SDK (`ai`, `@ai-sdk/react` and `@ai-sdk/workflow` are optional peers).

- `createAiChat` in `better-supabase/blocks/ai-chat` keeps chats, a branching message tree, runs, tool approvals, feedback, share links, a model catalog per plan and moderation events; `/blocks/ai-chat/react` adds `useAiChats`, `useAiChatTree`, `useAiModels` and `useAiShare`. Messages use a canonical format (`aiMessageSchema`, `schemas/ai-message-v1.json`, `SPEC_PINS.aiMessage`).
- `createAiFiles` in `better-supabase/blocks/ai-files` stores uploads in two steps with policies that follow the file row, and versioned documents. `/ai-sdk/files` adds `aiFileDownload`, `saveGeneratedFiles` and `providerFile`.
- `better-supabase/ai-sdk` adds message converters, AI Gateway helpers and job handlers, `createAssistant` in `/ai-sdk/chat` serves a resumable chat route, and `useAssistant` in `/ai-sdk/react` is `useChat` wired to it.
- `/ai-sdk/workflow` runs answers as Workflow SDK workflows with `durableChat` and `durableTurn`, and `useDurableAssistant` is the client half. `createAiChat(...).runs` reads run steps, and `createHarnessSessions` reads harness sessions.
- Harness sessions are read on the server only, the idle-stop job skips a sandbox whose session a turn holds, and the chat list hooks keep every loaded page on a live update and ignore stale responses.
