---
"better-supabase": minor
---

Block client methods that arrived with the e-invoicing, DSAR, regulatory filing, OSCAL, moderation, evals, guardrails, prompts, e-prescribing and agent checkout work now take one object input, like every other block method. For example `invoices.sendEInvoice({ invoice, format, channel })`, `dataLifecycle.verifyDataSubjectRequest({ requestId, method })` and `incidents.submitFiling({ incidentId, regime, stage, input })`.
