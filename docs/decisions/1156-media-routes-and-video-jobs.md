# 1156: Add media routes and video jobs to ai-sdk/chat

- Status: accepted
- Date: 2026-11-21

## Context

Image, speech and video generation needed an access check, metering and Storage
output like the completion routes have. Installed `ai` 7.0.179 exports
`generateImage`, `experimental_generateSpeech`, `experimental_startVideo`,
`experimental_getVideoStatus` and `experimental_generateVideo`. The gateway
returns `asyncJob.webhookSigningSecret` only in the start response, and neither
`ai` nor `@ai-sdk/gateway` 4.0.152 exports a function that verifies a video
webhook, and ai-sdk.dev documents no signature scheme.

`src/ai-sdk/gateway-policy.ts` (the org gateway policy) is not on origin/main.

## Decision

`createMediaRoute` and `createVideoRoutes` (`src/ai-sdk/chat/media.ts`) take the
model call as a callback, run `authorize` and the quota first, tag the gateway
call, and store output with `saveGeneratedFiles`. Video is a row in a
`VideoJobStore` the app owns. The webhook route trusts nothing in its body
except a `jobId`: it asks the provider for the status and acts on that answer.
The policy hook is skipped and noted in the docs until `gateway-policy.ts`
lands.

## Alternatives considered

Verifying a signature ourselves: rejected, the scheme is not documented, so we
would guess at it. A new SQL module for jobs: rejected, an interface lets the
app reuse its own table.

## Consequences

Missing evidence: a documented, exported webhook verifier. When one ships the
webhook can verify instead of re-check. The docs show the routes inline.
