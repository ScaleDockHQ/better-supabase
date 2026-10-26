---
"better-supabase": minor
---

Blocks over the app's own tables take more of their shapes, all opt-in:

- `pipelines`: with `status.follow`, an insert that sets the status and no stage lands on the first active stage whose category maps to that status, instead of the first open stage overwriting the status.
- A `mappable` column with a `values` entry, even `{}`, no longer counts as a text column the module writes, so an enum there passes the adoption check. `employees` maps `employmentType` this way.
- `hiring` `saveJob` writes `not null` extra columns in the insert that creates the job.
- Per-action keys with fallbacks: `tasks` `permissions.create` and `permissions.delete`, and `options.authorCanDelete: false`; `employees` `permissions.create`, `contractsRead`, `contractsWrite` and `privateDetailsWrite`; `hiring` `permissions.create`, `score`, `jobsCreate` and `jobsUpdate`.
- `employees` contracts: `salary` and `currency` can map to `null`, `options.salaryUnits: "major"` reads and writes a major-unit salary column, and `options.contractOverlap: "allow"` adds an editable contract without the overlap check.
- `employees` `update` accepts the app statuses a value map lists after a label's first value, such as `offboarding`.
- `hiring` with `options.stages`: a move to an unmarked stage keeps a state that no stage marks, such as a rejection.
- Entity rename errors name `blocks.<name>.names`, the key the config takes.
