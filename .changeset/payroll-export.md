---
"better-supabase": minor
---

New `payroll-export` block (`better-supabase/blocks/payroll-export`): payroll runs that add up the approved time, leave and scheduled shifts of a period per person and hand them to the payroll provider.

- `create` collects a draft run for a period from `options.sources` (the installed ones of `time-tracking` and `leave` by default, `shifts` on request), `refresh` collects it again, and `get`, `list` and `delete` read and remove runs.
- `exportRun` renders the run through a `PayrollExportFormat`, a versioned port (`apiVersion: 1`), keeps the SHA-256 of the file on the run and locks it. `csvPayrollFormat` is the reference format; a provider's layout implements the port.
- A new run for a period that overlaps an exported run fails with `PAYROLL_PERIOD_EXPORTED`, and a locked run refuses a refresh, a delete or a different file (`PAYROLL_RUN_EXPORTED`).
- The permission keys are `payroll_export.read` and `payroll_export.export`; admins hold both. The `payroll-runs` recipe lists the runs.

Add `"payroll-export": {}` to `blocks`, run `better-supabase add payroll-export` and generate a migration.
