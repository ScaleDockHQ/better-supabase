---
"better-supabase": minor
---

`createAgentRuntime` applies the AI Gateway attribution in `prepareCall` and merges it into the call's `providerOptions` (the library's `user` wins, `tags` are the union, other keys keep the call's value) instead of replacing `providerOptions` in `prepareStep`. `createWorkflowAgentRuntime` in `better-supabase/ai-sdk/workflow` builds an AI SDK 7 `WorkflowAgent` from the same options: the tenant's `ask` tools, high-risk operations and your `toolApproval` check run as each tool's `needsApproval`, and `toolApprovalSecret` sets `experimental_toolApprovalSecret`. `agentRuntimeParts` and `mergeGatewayOptions` are exported for custom runtimes.
