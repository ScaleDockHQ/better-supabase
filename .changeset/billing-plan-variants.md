---
"better-supabase": minor
---

Billing plans can have several prices per plan key. `sql.modules.billing.options.plans.variant` names the catalog column that tells them apart (credit packs, seat tiers); `billing_plan_price(plan, billing_interval, variant)` picks one, and the row without a variant stays the default. `checkout` and `changePlan` take `variant`, and `checkout` takes `items` for more line items (add-on packages) next to the plan. The `billing` module moves to version 2: `better-supabase sql upgrade` drops the two-argument `billing_plan_price`.
