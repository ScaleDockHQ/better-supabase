---
"better-supabase": minor
---

`SupportUnavailableError` now carries the digest `SUPPORT_UNAVAILABLE_DIGEST`, so a Next.js `error.tsx` can recognise it, and a support cookie that is not a UUID now counts as no session instead of a store outage.
