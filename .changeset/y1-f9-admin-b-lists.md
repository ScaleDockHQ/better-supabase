---
"better-supabase": minor
---

Pages the SSO, service account and API key blocks by the block list contract
(ADR 1077). `sso` gains `domainPage`, `getDomain` and `providerPage`,
`service-accounts` gains `principalPage`, and `api-keys` gains `keyPage`, each
with facets and a count. Every list takes sorts, array filters, `q` and a keyset
cursor, and a `get` for an unknown id returns a `not_found` error. `keyPage`
without an `organizationId` lists the caller's personal keys, and the app's own
fields are parsed on every row of `keyPage` and `principalPage`. The SQL adds
`page_organization_domains`, `page_sso_providers`, `page_service_principals`
and `page_api_keys`, and the generated schema files need `better-supabase
upgrade`. The array methods keep working and are deprecated.

| Old                    | New                             |
| ---------------------- | ------------------------------- |
| `sso.domains`          | `sso.domainPage`                |
| `sso.providers`        | `sso.providerPage`              |
| `serviceAccounts.list` | `serviceAccounts.principalPage` |
| `apiKeys.list`         | `apiKeys.keyPage`               |
