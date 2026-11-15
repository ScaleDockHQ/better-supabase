---
"better-supabase": minor
---

`export` and `exportResponse` take a `format`. `csvFormat` is the default and
`ndjsonFormat` writes one JSON object per line with the content type
`application/x-ndjson`. Pass your own `ExportFormat` (`contentType`, an optional
`header` and `rows`) for another line-oriented format, such as TSV. Both
helpers and the type come from `better-supabase/blocks`.
