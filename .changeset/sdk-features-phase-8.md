---
"better-supabase": minor
---

The AI SDK, Chat SDK, Sandbox and Connect adapters follow the current SDK releases.

Behaviour changes to check:

- `better-supabase/ai-sdk/workflow` passes the tool approval policy to `WorkflowAgent` as `toolApproval` instead of wrapping each tool with `needsApproval`. A denied tool call now ends as an `execution-denied` result, which the model sees, instead of an error.
- `createAssistant` stores a stream that failed after it started as an `error` message, releases the run as `failed` with the error text, and calls `onFinish` with `status: "failed"`. Before, the answer was stored as `complete`.
- `GatewayAccessPolicyDeniedError` maps to a `forbidden` error with code `AI_GATEWAY_ACCESS_POLICY_DENIED`.

New:

- `aiBatches` accepts `output`, and batch results carry each item's parsed `output` or `outputError`.
- `inboxAdapter` accepts reasoning chunks and keeps them out of the message a contact reads. `reasoning: "metadata"` stores them in `metadata.reasoning`.
- `vercelSandboxes` takes typed `mounts` for Vercel drives (`@vercel/sandbox` 4.1), merged by path.
- `vercelConnectCredentials` takes `teamId` and `orgId` (`@vercel/connect` 2.9), and `channelConfig` supports `"resend"`.
- The Flags SDK page documents running without `FLAGS_SECRET` (`flags` 4.5).
