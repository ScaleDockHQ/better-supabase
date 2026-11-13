# 0845: Check subject reads per set, and quotas per tenant set

- Status: accepted
- Date: 2026-11-13

## Context

`comment_counts` read each record's conversation under the conversations
policy, which called `can_subject` once per conversation, and then
`comment_count_rows` called it again per conversation: two reads of the
record's table for each record in the list. `search_page`, `search_recents` and `search_favorites` also called
`can_subject` per candidate row.

`usage_quota` resolved a tenant's entitlements and plans on every call, so a
billing job that read quotas for many tenants and meters resolved the same
tenant's plans once per meter.

## Decision

- The subjects module adds `can_subjects(subject_type, subject_ids, action)`,
  a security invoker function that returns the ids the caller can act on in
  one read of the record's table, under the table's policies.
- `comment_counts` stays security invoker. It reads the readable ids with
  one `can_subjects` call, then calls the security definer
  `comment_count_keys(tenant, subject_type, subject_ids, readable)`. That
  function finds the conversations by key and counts their messages. A
  conversation with subject access counts only for ids in `readable` that
  pass `can_subjects` again as the owner, so a direct caller can't widen
  what it reads; tenant, member and guest access are checked as before.
  `comment_count_rows` is dropped.
- `search_page` checks each keyset batch, `search_recents` and
  `search_favorites` each distinct record type, with one `can_subjects` call.
- The usage module adds `usage_quotas_for(tenants, meters)`, which resolves
  each distinct tenant's entitlements and plans once. `usage_quota` is a
  security invoker wrapper over it, and the usage block's admin client gains
  `usage.quotas({ organizationIds, meters })`.

## Alternatives considered

- A security definer `comment_counts` that calls `can_subjects` itself: as
  the owner, the record table's policies don't apply, so a signed-out session
  (the sessions block's `bsb_session_active` policy) would read counts.
- Passing only the readable ids to the definer lookup: a guest reads a
  record's comments through a guest grant, not the record's table, and would
  get no counts.
- A cache of `can_subject` results per statement: Postgres has no statement
  scope for a cache that a policy can read.

## Consequences

Module versions: subjects 2, comments 10, search 5, usage 9. The scale test
`scale_comments_many_tenants` checks that `comment_counts` makes no
`can_subject` call and two `can_subjects` calls for a list, and
`scale_usage_quotas_for` that 160 tenant and meter pairs resolve entitlements
at most once per tenant and match `usage_quota` per pair. The security
definer baseline doesn't grow: `usage_quota` became invoker, and the search
module emits its statement trigger functions only when a type sets
`search.statement`.
