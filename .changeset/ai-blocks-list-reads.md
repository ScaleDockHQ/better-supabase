---
"better-supabase": minor
---

`prompts`, `ai-evals` and `ai-guardrails` gain a page read each:
`prompts.list`, `datasets.list` and `policies.list`. They take `organizationId`,
`limit` and `after`, return a `ListPage` and go through `access` like the other
methods. `prompts.list` returns each name with its latest version, version count
and labels; `datasets.list` adds item and run counts; `policies.list` returns
the policies an organization saved, ordered by agent and stage. They are backed
by the new `list_prompts`, `list_eval_datasets` and `list_guardrail_policies`
SQL functions, which `better-supabase upgrade` writes into the modules: run it
and apply the migration it generates. A hand-written implementation of the
`Prompts`, `AiEvals` or `AiGuardrails` interface needs the new method.
