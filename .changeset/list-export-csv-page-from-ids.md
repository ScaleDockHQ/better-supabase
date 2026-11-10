---
"better-supabase": minor
---

The new `better-supabase/list/export` subpath exports `exportListCsv`, which streams a cursor list as a CSV download page by page, and `pageFromIds`, which builds a cursor page from a page of ids and a function that loads rows by id. Text cells that a spreadsheet would run as a formula get a leading `'`. See the list page in the docs.
