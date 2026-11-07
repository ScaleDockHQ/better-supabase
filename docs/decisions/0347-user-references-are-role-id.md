# 0347: User references are named by their role

- Status: accepted
- Date: 2026-11-07
- Amends: 0246, 0247, 0345

## Context

The catalog test of ADR 0247 counted 31 columns that name `user` in a block
table (`owner_user_id`, `customer_user_id`). Every one of them references
`auth.users`, so the word says nothing the foreign key does not.

## Decision

- A column that references a user is named by the role the user plays, with
  `_id`: `owner_id`, `customer_id`, `reviewer_id`, `host_id`, `holder_id`,
  `assignee_id`, `speaker_id`, `hiring_manager_id`, `referred_id`, `actor_id`,
  `from_id` and `to_id`. A few take a name their table reads better with:
  `appraisee_id` (appraisals), `decider_id` (quotes), `grantor_id` (consents,
  which already has `given_by`) and `paused_by` (lifecycles, as `created_by`).
- The rename is an explicit `column` row of `api/naming.json` per table, applied
  by `codemod naming` to an installed app and by the fixture migration
  `20261107225000_bsb_role_id_names.sql`; a generated migration then replaces
  the functions that read them. SQL function parameters and the JSON keys the
  blocks send use the same names. The logical names in `columns` and the `Row`
  fields do not change.
- `scim_users`' `scim_user_id` in `scim_group_members` stays: it references the
  `scim_users` table, not `auth.users`, and the catalog test counts it.
- An app that adopts its own table keeps its column names and maps them in
  `columns`; the CentraKit validation project maps `actor_user_id` of its status
  history this way.

## Consequences

An app that reads one of these columns over `$client` or `queryRaw`, or calls a
function with a named argument, changes the name.
