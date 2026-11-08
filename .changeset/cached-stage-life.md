---
"better-supabase": minor
---

`bsb.cached()` and `bsb.bootstrap()` take `stage: "prefetch" | "navigation"`, which awaits `prefetch()` or `navigation()` from `next/cache` before the entry's context resolves, and `life: "max"`, the profile `{ stale: 300, revalidate: 2592000, expire: 31536000 }`. Without the gates, or inside a `"use cache"` scope where they throw, `stage` is skipped and development logs it once.
