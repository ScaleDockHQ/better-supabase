---
"better-supabase": patch
---

`gen` no longer writes a facet index that the table already has. A page whose facet
matches a block's own index (`(tenant_id, status)`) got a second, identical index and
doctor reported it as a duplicate index. The check compares the btree column lists in
the snapshot and ignores the `*_page_idx` indexes `gen` wrote earlier, so a second run
changes nothing. Sort indexes are always written, because the snapshot has no sort
direction.
