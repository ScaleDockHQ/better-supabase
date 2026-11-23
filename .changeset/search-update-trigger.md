---
"better-supabase": minor
---

Breaking: a record type with `search.from` must list `search.columns`, the columns of its own table the view reads; the config error names the record type. The search index trigger splits into `bsb_search_<type>_index` for inserts and deletes and `bsb_search_<type>_index_u`, which fires on `update of` the watched columns only when one of them changes value. On 1,000 rows of a view-backed type an update of an unlisted column drops from 71 ms and 1,000 trigger calls to 21 ms and none. The search block moves to version 6; run `better-supabase upgrade`. Doctor BS637 reports a column a source view reads that `search.columns` leaves out (ADR 1222).
