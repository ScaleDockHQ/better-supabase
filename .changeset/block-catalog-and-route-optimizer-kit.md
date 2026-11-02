---
"better-supabase": minor
---

`better-supabase/preset` now exports `BLOCK_CATALOG`: every block with its title, category, description, requirements, events and docs link, generated from the block manifests. `better-supabase/testing` adds `testRouteOptimizer`, the conformance kit for a `RouteOptimizer`. The named presets `cms`, `erp`, `manufacturing`, `care`, `qms`, `isms` and `ai-agents` now include `dam`, `payroll-export`, `periods`, `rfqs`, `e-prescribing`, `clinical-decision-support`, `lims`, `advisories`, `prompts`, `ai-evals` and `ai-guardrails`. A preset only gains blocks, so an app that installed one before can add the new blocks with `better-supabase add`.
