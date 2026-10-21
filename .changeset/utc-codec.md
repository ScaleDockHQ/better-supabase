---
"better-supabase": minor
---

Add `codecs: { timestamptz: "utc" }`. `timestamptz` columns stay `string`,
but every value is rewritten in UTC as ISO 8601 with a `Z` and keeps all its
fraction digits (`2026-10-21 07:10:00.123456+02` reads as
`2026-10-21T05:10:00.123456Z`). `infinity` passes through. The default stays
`"string"`.
