---
"better-supabase": minor
---

`bsb.kept(fn, { share: "public" })` keeps one entry for every visitor and fills it as the `anon` role, under RLS, without reading the request or using the service role. The fill reads only `tables` and `functions`. Doctor rule BS645 reports a public entry on a table that `anon` can't select.
