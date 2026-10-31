---
"better-supabase": minor
---

New `lims` block (`better-supabase/blocks/lims`): laboratory samples tested with methods that have specification limits.

- `saveMethod`, `archiveMethod` and `listMethods` keep methods with a unit, a lower and an upper limit and an optional form.
- `registerSample`, `getSample` and `listSamples` keep numbered samples (`SMP-1`) that move from registered to testing, completed and released or rejected.
- `recordResult` computes the outcome from the limits. An out of specification result opens a nonconformity case when the `cases` block is installed and emits `lims_result.flagged`.
- `releaseSample` refuses while the latest result of a method is out of specification.
- `options.instrumentQualification` requires every result to name an asset that holds that qualification on the test date. `instrumentStatus` answers the same question before the work starts.
- The permission keys are `lims.read`, `lims.write` and `lims.manage`.

Run `better-supabase add lims` and generate a migration.
