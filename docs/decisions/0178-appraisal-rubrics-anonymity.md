# 0178: Appraisal rubrics and reviewer anonymity

- Status: accepted
- Amends: 0167

## Context

ADR 0167 gave a cycle one rating per review. Teams want to rate several
competencies with different weights, and peer reviewers need protection from the
person they review and, in some companies, from managers.

## Decision

- A cycle owns an optional rubric in `appraisal_competencies` (key, name,
  weight above zero). It is fixed once the cycle is open. A review in a rubric
  cycle takes one rating per competency in `appraisal_review_ratings`, and the
  review rating is the weighted average. The appraisal rating is the weighted
  average of the competency averages over all reviews.
- Calibration can move single competencies
  (`calibrate_appraisal_competencies`, stored in `calibrations.competency_ratings`
  and `appraisals.calibrated_competencies`). The calibrated rating is the
  weighted average of the calibrated values over the averages. Sign-off events
  carry the competency results.
- `appraisal_cycles.anonymity` is `none`, `subject` (default) or `all`. A peer
  review is hidden from the appraised person, or from every reader but its
  author, through `appraisal_review_hidden`. The read policies of reviews and
  ratings and every function output use it, and `reviewerId` becomes `null`.
  The table keeps the reviewer; the `appraisal_review.submitted` event leaves
  `reviewerId` null for a peer in a hiding cycle.
- `share_feedback` lets the appraised person read manager and peer reviews and
  competency results after sign-off.

## Consequences

Adopted `appraisal_cycles`, `appraisals`, `appraisal_calibrations` and
`appraisal_reviews` gain columns, and the block adds two tables. The default
`subject` changes what an appraised person with `appraisals.read` sees of their
own peer reviewers. The service role still sees every reviewer.
