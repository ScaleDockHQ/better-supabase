---
"better-supabase": minor
---

Add `better-supabase/vercel-sandbox`. `vercelSandboxes({ sandboxes })` gives each chat its own Vercel sandbox: `forChat` registers it in the AI chat block's `ai_sandboxes`, creates or resumes it by name, and returns an AI SDK sandbox session that marks the row used. `stop` is the stopper for the block's idle-stop job. The `untrusted`, `gatewayOnly` and `brokered` presets set the sandbox's network policy; `gatewayOnly` and `brokered` add tokens at the firewall, so code in the sandbox never holds them. `@vercel/sandbox` (`>=3 <4`) and `@ai-sdk/sandbox-vercel` (`>=1 <2`) are new optional peers.

`better-supabase/ai-sdk` adds `codeTool()`, a tool that runs a Python, Node or Bash snippet in the call's `experimental_sandbox` with a timeout and an output cap. Hold each run for approval with `toolApproval` on the model call.
