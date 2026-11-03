---
"better-supabase": minor
---

`guardrailsMiddleware` in `better-supabase/ai-sdk` is an AI SDK 7 `LanguageModelMiddleware` that runs the ai-guardrails policy around `doGenerate` and `doStream`: a blocked input returns the refusal without calling the model, a redaction rewrites the prompt, and a streamed text block is held until `text-end` and emitted redacted. The text helper that was called `guardrailMiddleware` in `better-supabase/blocks/ai-guardrails` is renamed, because it never was a middleware.

| Old                                  | New                |
| ------------------------------------ | ------------------ |
| `guardrailMiddleware` (block export) | `guardText`        |
| `GuardrailMiddlewareOptions`         | `GuardTextOptions` |
