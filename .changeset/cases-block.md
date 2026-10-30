---
"better-supabase": minor
---

New `cases` block (`better-supabase/blocks/cases`): nonconformities, complaints, incidents and other cases per organization, from report to a verified close.

- Each organization starts with eight kinds from `options.kinds` (nonconformity, complaint, incident, near miss, observation, improvement, change request and audit finding). A kind sets the number prefix (`NC-`, `CMP-`) and what closing requires; `saveKind` adds your own. Each kind gets its own pipeline with the stages reported, investigating, acting, verifying, closed and canceled.
- `open` puts a case on its kind's first stage, `move` moves it on the board, `recordRootCause` records the root cause and `createAction` or `linkAction` adds containment, correction, corrective, preventive and improvement actions as work items of the tasks block.
- `blockers` lists what still stops a case from closing (`CASE_ROOT_CAUSE_REQUIRED`, `CASE_ACTIONS_REQUIRED`, `CASE_ACTIONS_OPEN`, `CASE_EFFECTIVENESS_REQUIRED`, `CASE_DOCUMENTS_NOT_REVISED`), and `close` or a move to a closing stage fails with the first one while any remains.
- A kind with `effectivenessAfterDays` sets the effectiveness check date after the last required action is done; the daily `effectiveness-due` schedule runs `notifyDueEffectiveness`, which notifies the owner and emits `case.effectiveness_date_reached`.
- `case_from_submission` is a forms submission handler, so a public form opens cases of the answers' kind or `options.intakeKind`.
- The `medications` block's new `missedCaseKind` option opens a case of that kind for each missed dose.
- The permission keys are `cases.read`, `cases.create`, `cases.write`, `cases.close` and `cases.manage`; the default member role reads and opens cases, and a case's owner may change and close it.

Add `cases: {}` to `blocks`, run `better-supabase add cases` and generate a migration.
