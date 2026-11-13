---
"better-supabase": patch
---

The service worker that `init` writes for Next.js keeps hashed `/_next/static` files in their own cache, capped at 512 entries and kept across deploys. It skips `/_next/static/service-worker/` and stores only responses marked `immutable`, so the cache no longer grows with every deploy.
