# 0112: Run chat sandboxes on Vercel Sandbox through an optional-peer adapter

- Status: accepted
- Date: 2026-10-27

## Context

The AI chat block keeps every sandbox a chat or a harness starts in
`ai_sandboxes`, and its idle-stop job stops them through a stopper the app
passes. The block names no provider, and the ai-chat page told users to
write the Vercel stopper by hand. Nothing in the library created, resumed or
locked down a Vercel sandbox, and an assistant had no tool to run the code it
writes. Invariant 1 keeps the core free of runtime dependencies, and
ADR 0036 makes every SDK integration an optional peer with a tested range.

## Decision

`better-supabase/vercel-sandbox` exports `vercelSandboxes()`, an adapter over
the block's `AiSandboxes`. It loads `@vercel/sandbox` and
`@ai-sdk/sandbox-vercel` through `importOptionalPeer`, types both
structurally (`tests/optional-peers.test-d.ts` checks the real modules), and
pins `@vercel/sandbox` at 3.6.1 because 3.7 and later pull `@vercel/oidc` 4,
which the trust policy rejects.

`forChat` registers the sandbox first, so the registry's tenant check runs
before anything starts, then calls `Sandbox.getOrCreate` with a name derived
from the chat. It doesn't use `AiSandboxes.forChat`: after an idle stop the
registry row is stopped but a persistent sandbox still exists under its
name, so resuming by name is the reliable path. A `networkPolicy` passed for
an existing sandbox is applied with `update`, so a brokered token is fresh on
every message. `stop` is the idle-stop job's stopper and treats a 404 as
stopped.

Credentials reach the VM only at the firewall. The presets are `untrusted`
(deny-all), `gatewayOnly(token)` and `brokered(credentials, ref, ...)`; the
last two add the token as a header transform for one domain, so code in the
VM never holds it, and `brokered` caps the session timeout at the token's
expiry.

`codeTool()` in `better-supabase/ai-sdk` runs a snippet in the call's
`experimental_sandbox`, so it works with any AI SDK sandbox session. It has
no approval option: AI SDK 7 deprecated `needsApproval` on a tool, and the
docs set `toolApproval` on the model call instead.

## Alternatives considered

- A `@vercel/sandbox` dependency in the core: breaks invariant 1 and puts an
  SDK in every app that never runs code.
- Wrapping the Vercel SDK ourselves instead of `@ai-sdk/sandbox-vercel`:
  duplicates the AI SDK's session contract and drifts from it.
- Environment variables or files to pass tokens into the VM: the code the
  model writes could read and leak them.
- `AiSandboxes.forChat` to find the running sandbox: misses a stopped
  persistent sandbox and creates a second one.

## Consequences

An app gets a sandbox per chat, its idle stop and a locked-down network in a
few lines, and the block stays provider-neutral. Another provider plugs into
the same registry with its own adapter, and `codeTool` works with it
unchanged. Moving to `@vercel/sandbox` 3.7 waits for the trust policy to
accept `@vercel/oidc` 4.
