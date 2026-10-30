---
"better-supabase": minor
---

New `inspections` block (`better-supabase/blocks/inspections`): audit programmes, inspections with a team and a checklist form, and findings that open cases.

- `saveProgram`, `approveProgram` and `closeProgram` keep the programmes of a period. `schedule` plans an inspection of one of `options.kinds` against any auditee subject, numbered `AUD-2026-001` through the numbering block or `AUD-` and its position without it.
- An inspection moves from `planned` through `start`, `complete` and `close`, or stops with `cancel`. Its team gives each member the role of lead, auditor, observer or auditee; `saveChecklist` fills in the checklist form, and `complete` fails with `INSPECTION_CHECKLIST_INCOMPLETE` until it is submitted.
- `addFinding`, `updateFinding` and `deleteFinding` record findings typed by `options.findingTypes`, with a clause and a compliance control the inspection `assesses` through the relations block.
- A finding of a type in `options.caseFindingTypes` needs a case: `raiseCase` opens one through the cases block and links it as `created_from`, and `close` fails with `INSPECTION_FINDINGS_OPEN` until each such finding has one.
- The permission keys are `inspections.read`, `inspections.write` and `inspections.manage`. A member with `inspections.write` acts on the inspections they are on the team of, as their role allows.

Add `inspections: {}` to `blocks`, run `better-supabase add inspections` and generate a migration.
