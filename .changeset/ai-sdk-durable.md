---
"better-supabase": minor
---

`better-supabase/ai-sdk/workflow` keeps more of the AI SDK 7 answer in a durable chat.

| Change                                    | AI SDK 7 field                                               |
| ----------------------------------------- | ------------------------------------------------------------ |
| `DurableAgentResult.error`                | `error` on the `WorkflowAgent` stream result                 |
| The save step keeps `data-*` parts        | `data-*` chunks and `message-metadata` of the UI stream      |
| `context`, `userId`, `organizationId`     | passed to the agent function as `DurableAgentArgs`           |
| `durableChat({ context })`                | typed per app: `durableChat<UI_MESSAGE, CONTEXT>`            |
| `resume({ startIndex: -5 })`              | `WorkflowChatTransport` negative `startIndex` for reconnects |
| `x-workflow-stream-tail-index` on streams | the World's stream tail index, counted in UI chunks          |

A result with an `error` ends the turn `failed` and saves the error on the run. `DurableTurnInput`, `DurableAgentArgs`, `DurableTurnDeps` and `DurableChatOptions` take the context type as a generic that defaults to `undefined`, so existing code compiles unchanged.
