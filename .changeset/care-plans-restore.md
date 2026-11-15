---
"better-supabase": minor
---

`carePlans.restore(planId)` brings an archived care plan back as a draft and
records `care_plan.restored`. The plan's actions stay ended, so add the actions
the client needs before you publish it again. A plan that is not archived is
returned unchanged. It needs `care_plans.publish`. Run `better-supabase upgrade`
and apply the migration.
