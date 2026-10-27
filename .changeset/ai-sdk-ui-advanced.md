---
"better-supabase": minor
---

The AI SDK integration covers more of the AI SDK UI.

- `createAssistant` takes `stream` (the `toUIMessageStream` options, such as
  `assistantMetadata`, `sendReasoning` and `sendSources`) and `validate`, which
  checks the user's message with `safeValidateUIMessages` and answers
  `422 AI_MESSAGE_INVALID`.
- `aiErrorToDbError` maps AI SDK and AI Gateway errors to `DbError`s with a fixed
  message per kind. A provider error when the answer starts now answers with its
  own status (a provider 429 answers 429); `aiErrorMessage` is the default
  `onError` for stream errors, so the provider's message no longer reaches the client.
- `createCompletionRoute` and `createObjectRoute` serve `useCompletion` and
  `useObject` with the quota check, gateway tags and usage in `onFinish`;
  `useAssistantCompletion` and `useAssistantObject` are the client hooks.
- `useAssistant` takes a message type and passes `onToolCall`, `onData`,
  `messageMetadataSchema` and `dataPartSchemas` to `useChat`; `assistantTransport`
  is exported, and the fields of `AssistantTransportConfig` other than `api` are optional.
