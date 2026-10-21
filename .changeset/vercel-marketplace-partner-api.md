---
"better-supabase": minor
---

The Vercel Marketplace block serves the Partner API. `marketplace.partnerApi({ resources, plans })` returns one handler for the installation, resource, secret rotation and plan routes. It verifies Vercel's OIDC token (signature against `/.well-known/jwks`, issuer, audience and expiry) and requires its `installation_id` to match the path, answering 401 or 403 as Problem Details. The installation's access token is sealed in Vault, so `accessToken` is now optional. Tenants are tracked per installation and resource, and an empty tenant the integration created is removed with it. A rotation revokes the previous secrets only after the new ones are issued.

`reportUsage` now sends one request per billing period, with the period total as `periodValue` and the part not reported before as `dayValue`, and no longer sends `planValue`. It moves the reported amount only after Vercel answers 2xx. `marketplace.usageRoute({ secret, usage })` runs it from a cron caller. The SSO exchange reads keys from `https://marketplace.vercel.com/.well-known/jwks`, the path Vercel's discovery document names. Run `better-supabase gen` to apply the module's version 2 upgrade.
