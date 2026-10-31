---
"better-supabase": minor
---

The `drive` block gets retention per label and a changes feed.

- `sweepRetention` (service role) moves nodes into the bin when a label on them has a data lifecycle policy of kind `drive_label_<name>` and the node was last changed longer ago than the policy keeps it. Drive holds, legal holds and check-outs skip a node.
- `changes(organizationId, { cursor })` returns the nodes that changed after a cursor, oldest first, with binned nodes as `removed`, for sync clients.
- Moving a node into the bin or back now updates its `updated_at`.

Run `better-supabase upgrade` and generate a migration.
