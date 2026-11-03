---
"better-supabase": minor
---

AI SDK 7 settings reach more of the library. `createAgentRuntime` sets `telemetry` (`functionId: "agent:<id>"`, `includeRuntimeContext: { organizationId: true }`) so `meterTelemetry` meters agent calls, and takes `telemetry`, `settings` (the other `ToolLoopAgent` settings), `prepareCall`, `prepareStep`, `compact` (`pruneMessages` options) and `toolApprovalSecret` (`experimental_toolApprovalSecret`). `rerankWith` and the memory extraction call pass the tenant, so `rerank` and `generateText` usage is metered. `searchTool` is `strict` and takes `modelOutput: { maxCharacters }`. `connectTools` takes `maxRetries` and `askUnlessReadOnly`. `useAssistant` calls the server's stop endpoint before it stops the local stream, and the completion and object routes settle `onFinish` when the request aborts. `WorkflowAgentRuntimeOptions` omits the options a `WorkflowAgent` has no setting for (`WorkflowOmittedOptions`).
