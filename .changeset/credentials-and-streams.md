---
"better-supabase": minor
---

`better-supabase/credentials` resolves third-party tokens from a `credential_ref`, and `better-supabase/streams` stores resumable output for chats, workflows and agents.

- `vaultCredentials()` keeps secrets in Vault through the `credentials` module and verifies inbound signed requests. `createServer` takes a `credentials` provider as `ctx.credentials`, `subjectFor(ctx)` gives the subject, `better-supabase/vercel-connect` adds `vercelConnectCredentials()`, and `testCredentialProvider` checks other providers.
- The `streams` module keeps ordered chunks with idempotent appends and a cancel flag, used by `postgresStreamStore`, `teeToStore`, `writeToStore` and `resumeFromStore`. `better-supabase/streams/redis` adds `redisStreamStore` (`redis` is an optional peer), and `testStreamStore` checks other stores.
- A tenant's `credential_ref` carries `tenant` (`tenantCredentialRef`, `credentialRefInTenant`): connectors, AI providers, the workflow builder and MCP refuse a ref from another tenant with `CREDENTIAL_REF_FOREIGN`, Vault stores tenant secrets as `tenant/<tenant>/<secret>`, and `vercelConnectCredentials` refuses a tenant ref for the app subject.
