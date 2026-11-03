---
"better-supabase": minor
---

Approval requests can ask for several items, each decided on its own. `approvals.request({ subject, input: { action, items } })` files `approval_items` with a permission and `dependsOn` per item, `decideItems` approves or rejects them (an item waits for its dependencies, and the request settles when none is pending), `recordCreated` stores the record an approved item created, and `settle` lets the service role close a request with a system decision that wakes `requestAndWait`. `get` returns `items`, and `decideForSubject` takes `decidedBy`. `approve` and `reject` refuse a request with items. The `approvals` SQL module moves from version 1 to 2, so run `better-supabase upgrade`.
