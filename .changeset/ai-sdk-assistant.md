---
"better-supabase": minor
---

`createAssistant` in `better-supabase/ai-sdk/chat` continues a turn after a tool approval and takes your `UIMessage` type as a generic.

| Option or field                | AI SDK 7 field                                              |
| ------------------------------ | ----------------------------------------------------------- |
| `toolApprovalSecret`           | `experimental_toolApprovalSecret` (HMAC-signed approvals)   |
| `AssistantRunResult.tools`     | `toUIMessageStream({ tools })`                              |
| `AssistantTurn.continuationOf` | `toUIMessageStream({ isContinuation })` through the same id |
| `createAssistant<UI_MESSAGE>`  | `safeValidateUIMessages<UI_MESSAGE>`, `onEnd` message type  |

When the client sends the stored assistant message with `approval-responded` parts, the assistant copies only the `approved` and `reason` fields onto the stored message, rejects a signature that differs from the stored one (403) and a decision with no pending request (409), then saves the answer under the same message id. `assistantBody` in `better-supabase/ai-sdk/react` sends that message after an approval. The `experimental_lowMemory` comment now names `experimental_streamTextLowMemory`.
