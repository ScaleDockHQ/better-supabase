---
"better-supabase": patch
---

`in` and `notIn` filters on PostgREST no longer quote values that read the same without quotes: uuids, numbers, booleans, ISO dates and times, enum values, slugs and emails. Values with a comma, parenthesis, quote, backslash or space, the empty string and the string `null` stay quoted. This matches what supabase-js sends, so a list of about 300 uuids fits the URL again instead of failing with `414 URI Too Long` at about 200. The filter means the same as before; only the request text is shorter.
