---
"better-supabase": minor
---

New block `better-supabase/blocks/vercel-marketplace` (`better-supabase add vercel-marketplace`): installations, resources, plans, invoices and meter reports for an app listed on the Vercel Marketplace. `createVercelMarketplace()` verifies webhooks (`x-vercel-signature`, HMAC-SHA1), applies `integration-configuration.removed` and invoice events (the newest event wins), exchanges SSO codes and verifies the `id_token` against Vercel's JWKS, submits invoices and reports usage with retries. Only the service role calls it.
