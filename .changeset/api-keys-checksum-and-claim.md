---
"better-supabase": minor
---

API keys end in a 6-character CRC-32 checksum (`<prefix>_<public id>_<secret><checksum>`, a 43-character base62 secret), so `verify` and secret scanners reject a mistyped key without a lookup; keys created before it still verify. `sql.modules.api-keys.options.prefix` sets the token prefix the SQL side defaults to, and `options.scopes: "catalog"` limits scopes to the authorization provider's permission keys. Scopes may now contain uppercase letters. `parseApiKey` returns a new `checksum` flag. `apiKeyClaims` and `apiKeyResolver` take `claim` (`{ name, scopes, tenant, roles, serviceRoles }`), `serviceRoles`, `allPermissions` and `tenantClaim`, so the request carries the claim an authorization provider's SQL functions read: scopes as a ceiling, and a tenant key as a service principal of its tenant. Under the provider access model `create_api_key` refuses the `*` scope (`API_KEY_SCOPE_WILDCARD`) unless `options.scopes` lists it.
