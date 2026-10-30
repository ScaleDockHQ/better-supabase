---
"better-supabase": minor
---

New `care-plans` block (`better-supabase/blocks/care-plans`): care plans for any client record, such as a customer, a resident or a member.

- A plan belongs to one subject and holds problems (with a code from `options.codeSystems`, such as `omaha`), goals with a target date and actions of kind `intervention`, `appointment`, `task` or `measure`.
- `publish` freezes the draft as a version, makes it the client's active plan, archives the plan before it and starts its actions. `create` with `copyFromPlanId` drafts the next plan from an earlier one.
- `evaluate` records what a goal reached; a new status becomes the goal's status. The daily `reviews` schedule runs `dueReviews`, which notifies the owner and emits `care_plan.review_due` or `care_plan_action.review_due` when a plan or an action comes up for review.
- A restrictive measure (`kind: "measure"`, one of `options.measureKinds`) waits for an approval before it starts, through the approvals block. `requestAgreement` asks the members who speak for the client to sign the active plan through the signatures block, which gains the signature meaning `agreed`.
- Guests granted a client see its published plans. A task action can open a work item in the tasks block.
- The permission keys are `care_plans.read`, `care_plans.write`, `care_plans.evaluate`, `care_plans.publish` and `care_plans.manage`; the default member role reads plans.

Add `"care-plans": {}` to `blocks`, run `better-supabase add care-plans` and generate a migration.
