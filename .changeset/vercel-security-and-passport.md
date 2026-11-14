---
"better-supabase": minor
---

Two new entries for apps on Vercel. `better-supabase/vercel-security` guards the sign-up, OTP and magic-link routes: `botIdGuard({ checkBotId })` refuses bots with a `problem+json` 403 (`BOT_DETECTED`), and `firewallRateLimit({ checkRateLimit, id })` answers a limited request with a 429 and `Retry-After` (a Firewall block is a 403 with `FIREWALL_BLOCKED`). `combineGuards` and `withGuards` compose them, and `botIdCheck` covers Server Actions. `better-supabase/vercel-passport` adds `verifyPassport(request, options)`, which verifies the Vercel Passport token against Vercel's keys through the shared JWKS cache and passes `{ iss, sub, claims }` to your `resolveUser`. `botid`, `@vercel/firewall` and `@vercel/passport` are optional peers that you pass in; the entries import none of them.
