---
"better-supabase": minor
---

Adds the list calls the example findings EX-800, EX-802, EX-1102 and EX-1103
asked for, all additive (ADR 1077). `donations` accepts `q` on `giftPage`,
`giftFacets`, `giftCount` and the pledge reads (donor id, payment reference and
note), and `warehouse.pickListPage` accepts `q` over the document id and type.
`reviews.queue` takes a list of statuses in `status` and matches a review in any
of them. `inventory` gains `locationPage`, `binPage` and `variantPage` with
their facets and counts, so a page that names or selects locations, bins and
catalog variants no longer reads them with `queryRaw`.

The SQL extends `list_gifts`, `list_pledges` and `list_pick_lists` with a search
filter, replaces `review_queue` with a version that has a `statuses` argument
(the old arguments still work), and adds `page_stock_locations`,
`page_stock_bins` and `page_stock_variants`, so the generated schema
files need `better-supabase upgrade`.
