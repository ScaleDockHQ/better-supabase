# 1159: Add typed tenant tool context and tool guardrails

- Status: accepted
- Date: 2026-11-21

## Context

`ai` 7.0.179 supports `contextSchema` on a tool and `toolsContext` on a call.
`InferToolSetContext` is not exported, so the type comes from
`StepResult<TOOLS>["toolsContext"]`. Guardrails covered messages, not tool
calls.

## Decision

`tenantToolsContext` and `tenantContextSchema` (`src/ai-sdk/tool-context.ts`)
carry the organization and user id into tools. `guardTools`
(`src/ai-sdk/guardrails.ts`) wraps `execute`: input check, then output check,
and streamed chunks are checked as they pass. A block returns the refusal as
the tool result.

## Alternatives considered

Middleware on the model: rejected, it does not see tool results of provider
executed tools or inputs after approval.

## Consequences

One cast carries a `SAFETY:` comment. Revisit when the SDK exports the context
inference type.
