---
"better-supabase": patch
---

The Vercel probe (`scripts/probe-vercel-tags.ts` and the Next.js example's `/api/probe/vercel-tags`) now checks the kept store too: a read on another instance (`--second`), an entry from the previous deployment, set, hit and miss latency, and 250 `expireTags` calls in one second. `--local` runs the same steps on `memoryKeptStore()`.
