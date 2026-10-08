---
"better-supabase": minor
---

Breaking: the `authorization` config key takes an `AuthorizationProvider` (API v1, from `better-supabase/config`), and every PermDock-specific setting and export is removed. `sql.modules.access.model: "permdock"` becomes `"provider"`, `entitlements.permdock` becomes `entitlements.memberships`, bucket and topic `permdock` policies become `access` policies with `scope` and `sql` templates, `permdockVerifier` and the `permdock` claim option of `apiKeyResolver` become the provider package's job and the neutral `claim` option, and doctor reads the provider instead of `permdock.config.ts`, the manifest and the catalog. `testAuthorizationProvider` from `better-supabase/testing` checks a provider, and `templateFunctions` from `better-supabase/sql` lists the functions a template calls. The [0.5 to 0.6 guide](https://bettersupabase.com/docs/migration/0.5-to-0.6) has the old-to-new table.
