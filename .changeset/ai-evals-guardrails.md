---
"better-supabase": minor
---

New `ai-evals` block (`better-supabase/blocks/ai-evals`). It stores eval datasets and items, runs them
against a prompt version and a model with `createEvalJob`, scores with `exactMatch`, `jsonSchema` and an
injectable `llmJudge`, compares two runs for regressions and exports a promptfoo config.
`items.addFromFeedback` copies rated `ai-chat` replies into a dataset. New `ai-guardrails` block
(`better-supabase/blocks/ai-guardrails`) with per-agent input and output policies: prompt-injection
heuristics, PII redaction, topic deny lists and a tool depth limit. It logs decisions as hashes, records
the `guardrail.blocked` event and offers `check` and `guardrailMiddleware`. Run
`better-supabase add ai-evals ai-guardrails` to install them.
