---
"better-supabase": minor
---

`durableTransport` and `useDurableAssistant` in `better-supabase/ai-sdk/workflow/react` take every AI SDK 7 `WorkflowChatTransportOptions` field except `api`: `fetch`, `onChatSendMessage`, `onChatEnd`, `maxConsecutiveErrors`, `initialStartIndex`, `prepareSendMessagesRequest` and `prepareReconnectToStreamRequest`. `useDurableAssistant` reads them from `transportOptions`. The library builds the request first (the approval body, `config.headers`), then your `prepareSendMessagesRequest` and `prepareReconnectToStreamRequest` extend or replace it, and its `headers` are honored. A reconnect that gets `204` resolves to no stream.
