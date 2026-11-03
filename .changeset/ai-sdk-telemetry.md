---
"better-supabase": minor
---

`meterTelemetry` keys each usage row on `ai-call:<callId>:<responseId>`, the AI SDK 7 `LanguageModelCallEndEvent.responseId`, and falls back to the step index when the provider returns none. It keeps at most 1,000 calls in flight and releases a call on the `onEnd`, `onAbort` and `onError` telemetry hooks, so an aborted stream no longer leaks its tenant.
