# 0213: Approve a request item by item

- Status: accepted
- Date: 2026-11-03

## Context

An agent run often wants several things at once: create an invoice, attach a
contract, send an email. `approvals` files one request per subject and action,
so the run either asked once for everything or filed a request per thing and
lost the link between them. A decider could not approve the invoice and refuse
the email, and a step that needs the invoice could not wait for it.

## Decision

The `approvals` SQL module moves to version 2 (upgrade step from 1, no data
change). It adds `approval_items` (`key`, `label`, `payload`, `permission`,
`depends_on`, `status`, `created_type` and `created_id`, `decided_by`) and four
functions:

- `request_approval_items` calls `request_approval`, so the caller, policy and
  record checks are the same, and writes the items in the same transaction.
  `dependsOn` may name only items listed before it, which rules out cycles.
- `decide_approval_items` decides items. An item with a `permission` needs the
  caller to hold it; one without follows the step's approvers. An item is not
  approved while a dependency is pending or rejected, and rejecting an item
  rejects its pending dependents, so the request cannot wait on an item that
  can never be approved. The request settles when no item is pending: approved
  when any item was approved, rejected otherwise. It then writes a decision,
  runs `approval_finalize` and records the same events as before.
- `record_approval_created` stores the record an approved item created, once.
- `settle_approval` is service role only. It writes a decision without an
  approver (comment `system: <reason>`), settles pending items to the outcome
  and fires `approval.approved` or `approval.rejected`, so `approvalWaiter` and
  `requestAndWait` wake.

`decide_approval` refuses a request with items. The TypeScript client adds
`request({ items })`, `decideItems`, `recordCreated` and `settle`, returns
`items` from `get`, and `decideForSubject` takes `decidedBy`. Self-approval
options are unchanged. No new event types: item decisions surface through the
request events.

## Alternatives considered

- One request per item: no shared settle and no dependencies between them.
- A new `items` argument on `request_approval`: it changes a signature that
  has five overloads to drop and the extra-columns argument. A wrapper keeps
  the old function as it was.
- Item events (`approval_item.decided`): more catalog and docs for little gain,
  since the request events already wake waiters. Revisit when a consumer needs
  per-item webhooks.

## Consequences

Agents ask once and get partial approval. A request with items takes no extra
columns and not a subject type another module decides. Installed apps run
`better-supabase upgrade` and generate a migration for the table and the
functions.
