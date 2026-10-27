---
"better-supabase": minor
---

The AI SDK integration follows `ai` 7. `createAssistant` reads `stream`, `usage` and `finalStep` from what `run` returns and builds the UI message stream with the standalone `toUIMessageStream`; a result with only the 0.31 members (`toUIMessageStream()`, `totalUsage`, `providerMetadata`) still works until 0.33, and a result without a stream answers `500 AI_CHAT_RUN_FAILED`. `usageOf` takes `usage` and `finalStep` (the old names still work), and the agent runtime stops on `isStepCount`. `validUIMessages` checks a stored history against the app's tools and schemas through `safeValidateUIMessages`. `connectTools` takes `redirect` and `protocolVersionDiscovery`, and `connectAll` sets them per server through `serverOptions`. `aiBatches` gains `list()` over the provider's batches.

| 0.31                                        | 0.32                            |
| ------------------------------------------- | ------------------------------- |
| `usageOf({ totalUsage, providerMetadata })` | `usageOf({ usage, finalStep })` |
| `AssistantRunResult.toUIMessageStream()`    | `AssistantRunResult.stream`     |
