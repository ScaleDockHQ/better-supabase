---
"better-supabase": minor
---

Appraisal cycles take a rubric of weighted competencies (`competencies`, `setCompetencies`, per-competency `ratings` and `calibrateCompetencies`) and an `anonymity` mode (`none`, `subject` or `all`, default `subject`) that hides peer reviewers in function outputs and row-level security, plus `shareFeedback` for the appraised person after sign-off. Adopted appraisal tables gain `anonymity`, `share_feedback`, `calibrated_competencies` and `competency_ratings` columns, and the block adds `appraisal_competencies` and `appraisal_review_ratings`. With the default, a person who held `appraisals.read` no longer sees who wrote a peer review about them. See ADR 0179.
