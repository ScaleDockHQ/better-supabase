---
"better-supabase": patch
---

The pgTAP file that `gen.entityPages` writes per page (`scale_list_<name>.test.sql`) now turns
`enable_sort`, `enable_incremental_sort` and `enable_bitmapscan` off next to `enable_seqscan`.
A sort that no index serves and a facet count that is not an index-only scan fail on any table
size, including the few rows of a local seed. Run `better-supabase gen` to rewrite the files.
