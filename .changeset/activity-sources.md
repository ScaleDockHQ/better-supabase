---
"better-supabase": minor
---

A record's activity timeline now includes its notification deliveries (with the `notifications` module) and its workflow runs (with the `workflows` module), as `delivery.<status>` and `run.<status>` entries with `source` set to `delivery` or `run`. Deliveries need `activity.read` and `notifications.send`, the same as the notifications client's `subjectDeliveries`; runs follow the `workflow_runs` read policy. `createComments().history()` takes `sources` to pick which kinds of entry to return, and `list_activity` gains a matching `sources text[]` argument. The comments module moves to version 6, so re-run `better-supabase sql sync`.
