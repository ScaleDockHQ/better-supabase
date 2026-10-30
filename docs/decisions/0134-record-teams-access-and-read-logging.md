# 0134: Decide per-record access through record teams, and log reads of opted-in types

- Status: accepted
- Date: 2026-10-29

## Context

Care, CRM and case work need access per record, not per tenant: only a
client's care team reads the client's file, the account team edits its
customers, and the investigators of a case see the case. Tenant permission
keys can't express that, and the subject registry (ADR 0020) only grants an
action through a key, a provider row set, an owner column or a check
function (`subjects.<type>.permissions`). Care also needs emergency access
(break the glass) and a log of who read which client, with the NEN 7513
fields: who, which client, when, which action, which application function
and whether it was an emergency.

## Decision

A subject type opts in with `config.subjects.<type>.team: { actions }`. The
`subjects` block then installs `subject_members`, one row per user or team
(from the `teams` block) on a record, with a role
(`blocks.subjects.options.recordTeam.roles`, default `lead` and `member`) and
the days it counts (`starts_on` and `ends_on`, both included).
`can_subject` and `can_subject_for` grant the listed actions to members whose
dates include today; an action with a `permissions` entry ORs the team grant
with the key, and an action only `team` lists is granted to the team alone.
`add_subject_member`, `end_subject_member`, `list_subject_members` and
`my_subjects` manage and read the teams, gated by `subjects.manage` (admin) or
`can_subject(..., 'manage')`, and emit `subject_member.added` and
`subject_member.ended`. Ending a membership sets `ends_on`, so access stops the
next day without a job. `subjectRowReadable(ctx, alias)` in
`src/sql/subjects.ts` is the read rule blocks attached to a record use in
their policies. The `represents` relation kind targets only the types with a
team when one declares it.

Emergency access is a time-boxed `subject_members` row with `emergency = true`
and a reason, opened through access requests and reviewed afterwards (PR 30).
Reads of a type with `auditReads: true` call `record_subject_read` and land in
the audit log under category `read` with the NEN 7513 fields (PR 31). Both
build on this table and are recorded here so the three stay one model.

## Alternatives considered

- A per-record permission key in the authorization provider. It moves the
  care relationship out of the database the policies read, and every app
  would need a provider that stores per-row grants.
- A table per block (care team, account team, case team). Each block would
  repeat the dates, roles, team expansion and events, and `can_subject` would
  need to know about all of them.
- Revoking access with a scheduled job at the end date. Dates checked in the
  query need no job and can't drift when the job is late.

## Consequences

Any registered type gets record teams by adding one key, and every block that
asks `can_subject` follows them. Blocks that check a record's `read` entry
inline, and render before `subjects`, still check only the key; moving them
onto `can_subject` is follow-up work. `my_subjects` answers "my clients" and
"my accounts" in one call. The team check runs inside every `can_subject`
call for an opted-in type, so `subject_members` is indexed by user and tenant.
Revisit if a provider needs to own record teams, through a versioned
contribution rather than a silent change.
