---
"better-supabase": minor
---

Three blocks get the reads and clients the example app was missing. Run `better-supabase gen` and `db diff` to pick up the new functions.

| Before                                                                         | After                                                                                                                                                                  |
| ------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `field-encryption` had no member read                                          | `field_key_status()` and `createFieldEncryption().keyStatus()` from `better-supabase/blocks/field-encryption`                                                          |
| `vercel-marketplace` reads needed the service role                             | `installationFor(tenant)` and `resourcesFor(tenant)` for tenant members, and `VERCEL_MARKETPLACE_CLIENT_ID` and `VERCEL_MARKETPLACE_CLIENT_SECRET` in the manifest env |
| `impersonation` had no client, apps called `db.$client.schema("api").rpc(...)` | `createImpersonation()` from `better-supabase/blocks/impersonation` with `request`, `approve`, `start`, `end` and `list`                                               |
| `SessionProvider` read `caller_authz_version()` from `api` only                | `schema` prop on `SessionProvider` and `realtimeVersionSource`, default `api`                                                                                          |
| `doctor` BS502 read only the app's `.gitignore`                                | it reads the files up to the repository root and ignores `!` lines                                                                                                     |
| `gen --check` listed stale files                                               | it adds a subject, search and other count (`data.drift`)                                                                                                               |
