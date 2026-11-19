---
"better-supabase": minor
---

Calls an adopter looped or wrote by hand:

- `deadlines.computeMany({ items, prune })` (`compute_deadlines_many`) computes up to 1000 subjects in one request and answers each item with its deadlines or its error; with `prune`, each subject's pending deadlines of other jurisdictions go first. `deadlines.prune({ subjectType, subjectId, keepJurisdiction })` and `deadlines.forget(subject)` (`prune_deadlines`) delete a subject's pending deadlines of other jurisdictions, or all of its deadlines. A record type with `cascade: true` now deletes its deadlines when its row is deleted.
- `organizations.updateInvitation` takes `changes.onAccept` (`on_accept` on `update_invitation`) to replace the roles or teams an invitation grants on accept, with the checks `invite` makes.
- `organizations.resendInvitations({ invitationIds })` (`resend_invitations`) and `teams.purgeMany(ids)` (`purge_teams`) act on up to 1000 records in one request, all or nothing.
- `blocks.audit.options.subjectColumns.<column>.tables` reads another key for one table's rows, so `{ job_id: { type: "uuid", tables: { "public.jobs": "id" } } }` fills `job_id` on the jobs table's own entries.
