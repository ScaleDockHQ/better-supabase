---
"better-supabase": minor
---

`defineListQuery` takes relation facets, a free multi-column sort and date buckets.

- A facet can be `{ relation: "notes", column: "kind" }` and filters on a related table (`some` for a to-many relation). It has no counts, so its `facetCounts` entry is empty.
- `freeSort` from `better-supabase/list/order` lets the caller send `order=status:desc,name` (up to three columns). `ListQuery.order` holds the terms, and `list.parsers.order` is the URL parser.
- The `@bsb buckets column=<column> filter=<columns>` tag renders `<table>_date_buckets`, and `listDateBuckets` from `better-supabase/list/buckets` calls it and narrows by the facet values of a list query.

Existing lists keep working: the new `ListQuery.order` field and the new `FacetInfo.relation` field are optional. The `./list` entry grew by 1.3 KB gzip. Run `better-supabase table <name> enable buckets` and `db diff` to add the function to a table.
