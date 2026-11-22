# 1110: Record the 0.82 findings that did not reproduce

- Status: accepted
- Date: 2026-11-22

## Context

The 0.82 plan listed findings from the CentraKit report. Several did not reproduce against this repository, and a later reader should not look for a fix that was never needed.

## Decision

No code changed for these, and each reason is on record.

- BS112 reports 58 functions in validation-centrakit, not the plan's count. The baseline groups them with one reason.
- The empty `saas`, `finance` and `recruiting` slices: rendering every block slice produces none, because the composite entry is only built when every part is installed.
- No `sameTenant` or BS315 baseline codemod move: the entry options cannot be shown to match the tag, and a baseline lists accepted findings, not exemptions.
- No help snapshot for the codemod subcommands: the snapshot covers top-level commands.
- The import gaps note and the plan 057 B15 note are not in the repository, so those fixes follow the plan's wording.
- No cancel hook for expense reports and non-employee timesheets: their status follows the approval request.
- 35 tenant tables declare no lifecycle; `tests/sql/lifecycle-declared.test.ts` lists them and fails when the list grows.
- `columnsSchema` already reads `not null default`, so insert optionality needed no change, and there is no `sql size` command to extend.
- 34 files fail in `pnpm supabase:test` on the merge base and here, with the same list, so they are not caused by this release.

## Alternatives considered

Silently dropping the items was rejected: the next audit would reopen them.

## Consequences

The list is the reference when someone asks again. Revisit an item when a report reproduces it.
