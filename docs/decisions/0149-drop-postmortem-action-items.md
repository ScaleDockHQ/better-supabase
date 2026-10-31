# 0149: Drop postmortem action items before 0.47 ships

- Status: accepted
- Date: 2026-10-31
- Supersedes: the postmortem line of 0147

## Context

0147 kept `actionItems` and the `action_items` column until 0.48, because the
copy into tasks has to run on a database before the column goes. The schema
diff (`db diff`) runs after the block upgrade steps, so an upgrade step can do
the copy first. 0.47 is not released, so no app depends on the column yet.

## Decision

- `incidents` moves to SQL version 3. Its upgrade step (`from: 2`) copies each
  item of every postmortem without linked actions into a task through
  `add_incident_postmortem_action`, then drops `action_items`. It runs before
  the schema diff, so the diff only sees a column that is already gone.
- When items exist and the copy can't run (no tasks block, or the function is
  missing), the step raises an error and leaves the column. Data is never
  dropped silently.
- `savePostmortem` no longer takes `actionItems`, `Postmortem` has no
  `actionItems`, and `save_incident_postmortem` refuses the key.
- The foreign key column renames stay deprecated until their own PRs.

## Alternatives considered

- **Keep the column until 0.48.** Carries a dead column through one more
  release.
- **Drop in the diff migration only.** Loses the items on databases that were
  never copied.

## Consequences

- A 0.46 database with items and no tasks block must add `tasks` or clear the
  column before `upgrade` succeeds.
