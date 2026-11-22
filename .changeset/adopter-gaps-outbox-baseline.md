---
"better-supabase": patch
---

Fix five gaps an adopter found on 0.82:

- `baseline apply` moves every `xid8` or `xid` value of the restored rows that is ahead of the new database's transaction counter back to the restoring transaction, and `outbox_register` never starts a consumer past the current snapshot, so a consumer registered on a fresh stack no longer skips new events.
- `submit_expense` lets the line manager or the update key resubmit a rejected expense whose owner has no account; an owner with an account still resubmits their own.
- The relay's receive check reads its probe message back by its typed primary key, so it no longer scans `realtime.messages`.
- `baseline apply` removes its temporary folder when unpacking the storage tarball fails.
- `cancel_leave_request` refuses a rejected request only while it is not approved, matching the status it reports.
