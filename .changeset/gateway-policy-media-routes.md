---
"better-supabase": minor
---

`createMediaRoute` and `createVideoRoutes` in `better-supabase/ai-sdk/chat` take a `gatewayPolicy`
option. Pass the reader that `gatewayPolicyReader` returns, and the organization's gateway policy is
applied to the `providerOptions` your `run` and `start` callbacks receive. A policy that fails to
load answers with its error instead of running the call. Without the option nothing changes.
