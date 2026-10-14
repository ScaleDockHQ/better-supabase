---
"better-supabase": minor
---

The audit block reverts row changes: `audit.revert(entryIds)` (SQL `revert_audit_entries`) writes the old values back as the caller, newest entry first, all or nothing, and refuses with `ROW_CHANGED_SINCE` when a row changed after the entry. Members need the new `audit.revert` permission, which admins have by default. The result carries an undo token that reverts the revert. The saved-views read policy now evaluates `auth.uid()` once per query when the teams module is installed.
