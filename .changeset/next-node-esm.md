---
"better-supabase": patch
---

`better-supabase/next` loads in plain Node ESM, such as Vitest without inlining. It imported `next/navigation` without a file extension, which Node cannot resolve because `next` has no `exports` map. It now imports `forbidden`, `notFound` and `unauthorized` from their server-safe Next modules, which also keeps route handlers building under Turbopack.
