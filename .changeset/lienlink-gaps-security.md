---
"better-supabase": minor
---

Access fixes from an adopter running an authorization provider with own and team level grants:

- A record type permission registered with `rows`, `owner` or `check` is now checked on the record's row by the `attachments` upload and manage checks, so a member whose key covers only their own or their team's records can attach files to those records (ADR 1094). The `deadlines` read checks let such a member read the deadlines of the records the grant reaches when `blocks.deadlines.permissions.read` is the record type's read key. Plain keys are checked in the tenant as before.
- `import_note_issue`, `import_note_warnings` and `import_clear_issues` are revoked from `public`, `anon` and `authenticated`; only the import functions call them.
- The `contacts`, `imports`, `teams` and `notifications` functions check the service role with the shared `SERVICE_CALLER` check instead of the deprecated `auth.role()`, so a direct admin connection passes as it does in the other blocks.
- `team_members` has a composite foreign key `(tenant_id, team_id)` to `teams`, so a member row can't point at another tenant's team. `teams`, `companies`, `people`, the contact `locations`, `bank_accounts` and `channels` tables, `attachments` and `ledger_transactions` get a unique `(tenant_id, id)` index, so app tables can reference them with a composite foreign key (doctor BS217). An upgrade fails on an existing `team_members` row whose team is in another tenant; move or delete it first.
- `blocks.organizations.permissions.readPlatform` names a platform key whose holders read every organization through the table's read policy.
