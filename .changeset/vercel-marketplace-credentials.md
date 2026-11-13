---
"better-supabase": minor
---

`createVercelMarketplace` takes `clientId` and `clientSecret` as optional and reads them from `VERCEL_MARKETPLACE_CLIENT_ID` and `VERCEL_MARKETPLACE_CLIENT_SECRET` in the new `env` option (`env: process.env`), so a settings page can build the client for `installationFor` without holding the secret. Without them, `verifyWebhook` answers `false`, and `handleWebhook`, `exchangeSso` and the Partner API's token check return a `forbidden` error with the hint `MARKETPLACE_CREDENTIALS_MISSING`, so a missing client id never matches a token without an audience. `VERCEL_MARKETPLACE_ENV` names the two keys.
