# 0167: Appraisals are review cycles over enrollments, forms and approvals

- Status: accepted
- Date: 2026-10-31

## Context

A performance review runs in a cycle: each person gets a self review, a manager
review and peer reviews, a calibration session evens out the ratings, and a
manager signs the result off. `enrollments` already tracks a subject through
program steps, `forms` holds longer answers, `goals` holds objectives and
`approvals` holds sign-offs. Nothing ties them into a cycle with ratings.

## Decision

`appraisals` is a block (`better-supabase/blocks/appraisals`) with five tables:
`appraisal_cycles`, `appraisals`, `appraisal_reviews`,
`appraisal_calibrations` and `appraisal_goals`. Every table is adoptable
(ADR 0098). The block requires memberships, permissions and subjects, and
integrates with `enrollments`, `forms`, `goals`, `approvals`, outbox and audit
when they are installed.

- A cycle is `draft`, `open` or `closed`. `open_appraisal_cycle` takes
  `{ subjectUserId, managerId, peerIds }` assignments and creates one
  appraisal per person with a self review, a manager review when a manager is
  set and one review per peer. Calling it again adds people and never
  duplicates one.
- An appraisal is a subject (`appraisal`) that moves `pending`, `reviewed`,
  `calibrated`, `awaiting_signoff`, `signed_off`. It becomes `reviewed` when
  its last review is submitted, and its rating is the average of the
  submitted ratings.
- A review is written only by its assigned reviewer. Ratings are whole numbers
  from 1 to 5. Longer answers live in a `forms` submission whose id the review
  stores, so the block does not copy forms.
- A calibration changes the rating of a reviewed appraisal in an open cycle
  and keeps the previous rating and the reason. The review average stays.
- Goals are linked by id (`set_appraisal_goals`), so `goals` stays the owner.
- Sign-off with `approvals` files a request under the policy for appraisal
  `sign_off` (default: a holder of `appraisals.manage`) and the appraisal waits
  as `awaiting_signoff`. The block contributes the approve and reject
  handlers. Without `approvals`, a holder of `appraisals.manage` signs off
  directly. A cycle closes once every appraisal is signed off.
- With `enrollments` and a cycle `program`, each stage marks a step named
  `self_review`, `peer_review`, `manager_review`, `calibration` or `sign_off`.
- A member reads only the reviews they wrote. A holder of `appraisals.read`
  reads every review and calibration.
- Permissions are `appraisals.read`, `appraisals.review` and
  `appraisals.manage`, per ADR 0130. Events are `appraisal_cycle.created`,
  `.opened` and `.closed`, `appraisal.created`, `.calibrated` and
  `.finalized`, and `appraisal_review.submitted`.

## Alternatives considered

- **Store reviews as `forms` submissions only.** Ratings need to be queried
  and averaged, and a reviewer's access follows the assignment.
- **A second approval table.** `approvals` already has policies, steps and
  one-time consumption.
- **Anonymous peer reviews.** Reviewer ids are kept so a manager can follow up;
  hiding them from the subject is the default, and anonymity toward managers
  is deferred.

## Consequences

- Cycle dates are informational. Nothing opens or closes a cycle on a
  schedule; apps call the functions.
- A peer who has no `appraisals.review` permission can't submit, so a role
  that has `appraisals.manage` only needs `review` too.
- Rubrics with several rated competencies per review are deferred. A review
  holds one overall rating and a forms submission for the rest.
