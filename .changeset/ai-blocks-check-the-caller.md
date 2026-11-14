---
"better-supabase": patch
---

Security: the service-role AI blocks `prompts`, `ai-evals` and `ai-guardrails`
did not check which organization or permission a call acted for, so an app
that skipped its own check could read or write another organization's prompts,
datasets, runs and decision log. Each block now takes an optional `access`
(`{ organizationId, allowed, permission }`). With it, every method fails with
`forbidden` unless the caller has an organization and the permission, a call
must name that organization, a dataset or run of another organization reads as
`not_found`, and `decisions.purge` is refused. Without it the blocks behave as
before. `ai-evals` also gains `datasets.get` and the `get_eval_dataset` SQL
function, which `upgrade` writes into the module; run `better-supabase upgrade`
and apply the migration it generates. Apps that call these blocks for a
signed-in caller should pass `access`.
