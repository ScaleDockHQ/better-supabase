---
"better-supabase": minor
---

Server auth can run hermetic. `auth.jwks: false` (or `null`) verifies against no keys and never fetches one, ignoring `SUPABASE_JWKS` and `SUPABASE_JWKS_URL`; `null` used to fall through to the JWKS URL. `createServer({ env })` also takes the variables as an object (`{ SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY }`) and loads only those, never filling a missing one from `process.env`. `createTestSigner().jwks` is typed so it passes to `auth.jwks` without a cast.
