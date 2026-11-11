# 0675: Read a comment's conversation by key, ask isApprover inside the approval set, and read usage plans once

- Status: accepted
- Date: 2026-11-11
- Amends: 0644

## Context

An adopter measured three reads on its hosted database. `list_comments` took
about 4.5 s for one comment when the caller was a member of many tenants with
about 150 record conversations. A count of pending approvals took 555 ms for a
member with 61 pending requests across 10 tenants. `usage_overview` was the
largest total database time, because a cron calls it per tenant.

## Decisions

### Comment reads look up the conversation by key

`comments_json` joined the messages to `conversations` and `comment_tasks`.
The planner expected 100 rows from the function scan and hash joined the whole
readable conversations table, so the conversations policy ran for every
conversation the caller could read. `message_authors` had an `exists` on
conversations that the planner turned into a semi join the other way round.
`comments_json` now reads the conversations of the distinct conversation ids
of its messages, and the work items of its message ids, in materialized CTEs.
`message_authors` checks readability for the distinct conversations of the
requested messages only, as an uncorrelated array.

`scale_comments_many_tenants` (50 tenants, 150 project conversations with one
comment each, one thread of 50) counts the `can_subject` calls of each read:

| Read                            | Before      | After       |
| ------------------------------- | ----------- | ----------- |
| `list_comments`, one comment    | 154 (31 ms) | 5 (9 ms)    |
| `list_comments`, 50 comments    | 401 (93 ms) | 252 (60 ms) |
| `comment_counts`, three records | 55 (11 ms)  | 55 (12 ms)  |

A read now costs a few checks per message on the page, not one per readable
conversation. The file fails when reading one comment takes ten checks or more.

### Not done: inlining the conversations policy

The conversations read policy was inlined with `registryReadable`, with the
types of messaging and channels sent to `can_subject` in every inline subject
policy, so no other policy plans the conversations policy again. `can_subject`
calls fell to 1 for one comment, but the policy now has 40 branches: planning a
read of one conversation took 15.7 ms, and `list_comments` went from 9 to 173 ms
on the fixture, because each statement in the function plans the policy again.
It confirms ADR 0644. The policy keeps `can_subject` until the subject list it
inlines can be limited to the types an app's conversations use.

### approval_eligible_ids asks isApprover per request

With an authorization provider that defines `isApprover`, the set form called
`approval_eligible(id)` for every pending request no set rule matched. That
runs every approver rule again in a separate function call per request, in
every tenant. The set form now calls the provider's `isApprover` on the
request's columns with the current step's approvers (the escalation set once
the step escalated), as `approval_eligible` does. On PGlite with 2,000 pending
requests in ten tenants and the permission in one, `approval_eligible_ids()`
took 349 ms before and 5.5 ms after; with 61 requests, 13.3 ms and 3.1 ms. The
rows are the same, and a unit test compares the set form with
`approval_eligible` for a provider cover.

The base set still holds every pending request when no tenant is passed. A
named approver or the provider can let a user decide in a tenant they are not
a member of, so limiting the set to the caller's tenants would change who may
decide.

### usage_overview reads the plans once

0.58 already resolves the quotas, the windows and the counters of
`usage_overview` as sets. Its quota filter still called `tenant_entitlements`
and `tenant_plans` once per quota row, 14 calls for 20 meters on the fixture.
The quotas that apply are now one materialized CTE whose plan arrays are
uncorrelated subqueries: one call each. `scale_usage_overview` checks the count
and that the result equals `usage_status` per meter.

## Consequences

`better-supabase upgrade` rewrites `comments`, `messaging` and `usage`; the
migration replaces `comments_json`, `message_authors` and `usage_overview`.
Apps with an `isApprover` provider get a new `approval_eligible_ids` body.
