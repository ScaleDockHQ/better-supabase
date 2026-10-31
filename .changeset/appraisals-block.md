---
"better-supabase": minor
---

New `appraisals` block (`better-supabase/blocks/appraisals`): review cycles with self, peer and manager reviews, calibration sessions, goals and sign-off.

- `createCycle` and `openCycle` start a cycle and create one appraisal per person, with a self review, a manager review and one review per peer. `closeCycle` ends it once every appraisal is signed off.
- `submitReview` takes a rating from 1 to 5, comments and an optional `forms` submission id. Only the assigned reviewer submits, and a member reads only their own reviews.
- `calibrate` moves a reviewed rating with a reason and keeps the previous value. `setGoals` links goals from the `goals` block.
- `signOff` signs an appraisal off. With the `approvals` block it files an approval and the appraisal waits as `awaiting_signoff`. With `enrollments` and a cycle `program`, each stage marks a program step.
- The permission keys are `appraisals.read`, `appraisals.review` and `appraisals.manage`.

Add `appraisals: {}` to `blocks`, run `better-supabase add appraisals` and generate a migration.
