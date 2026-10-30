---
"better-supabase": minor
---

New `risks` block (`better-supabase/blocks/risks`): a risk register per organization.

- Risks are numbered (`RSK-0001`), belong to a category from `options.categories` and are scored on a likelihood by impact matrix. Each organization gets a 5 by 5 default matrix with low, medium, high and critical bands; `saveMatrix` adds your own, and `options.defaultMatrix` replaces the default.
- `assess` scores a risk before and after controls (inherent and residual) and keeps every assessment, each frozen as a version.
- `setTreatment` records mitigate, transfer, accept (needs `risks.manage`) or avoid, `review` moves the next review date ahead by the risk's interval, and `close` closes it with a reason.
- `heatmap` counts the open risks per matrix cell. `get` returns the barriers, the controls and other records linked with the `mitigated_by` relation kind.
- The daily `review-due` schedule runs `notifyDueReviews`, which notifies the owner once when a review date comes and emits `risk.review_date_reached`.
- The permission keys are `risks.read`, `risks.write`, `risks.assess` and `risks.manage`; the default member role reads the register.

Add `risks: {}` to `blocks`, run `better-supabase add risks` and generate a migration.
