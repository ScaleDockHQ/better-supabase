---
"better-supabase": minor
---

A write now expires its tags in the `bsb.kept()` store as well as in the Next.js cache, and the
request stats count every tag call in `tagCalls`. The Runtime Cache store sends one `expireTag`
call per 16 tags.
