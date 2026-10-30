---
"better-supabase": minor
---

Activities takes progress notes. An engagement has an `audience`: `team` keeps today's read rule, `subject` also lets guests with a read grant on a linked record read it, and `restricted` needs one of `restrictedRoles` on a linked record's team, the new `activities.read_restricted` permission, or to be its author or owner. Engagements also take a `category` (checked against `options.noteCategories`) and a `goalId`.

Engagements of a `options.lockTypes` type (default `note` and `report`) lock `options.lockAfterHours` after they are logged (default 24). After that, `update`, `complete` and `remove` fail with `ACTIVITY_LOCKED`. Notes logged before this release keep no lock. `amend(id, body)` adds a linked addendum (`amend_activity`, event `engagement.amended`), and `markError(id, reason)` flags an engagement as entered in error and locks it (`mark_activity_error`, event `engagement.marked_error`).

The subjects block adds `has_subject_role(subject_type, subject_id, roles)`, which checks the caller's record team roles.

Upgrade: re-run `better-supabase add activities` and `better-supabase add subjects`, then generate a migration. On your own engagements table, map the new columns to `null` in `blocks.activities.columns.engagements` to leave them out. To keep every engagement editable, set `blocks.activities.options.lockTypes: []`.
