---
"better-supabase": minor
---

Add `better-supabase/claims`. It exports the claim names (`PERMISSIONS_CLAIM`, `MEMBERSHIPS_CLAIM`, `FEATURES_CLAIM`, `AUTHZ_VERSION_CLAIM`, `PERMISSION_CAP_CLAIM`, `PERMISSIONS_TRUNCATED_CLAIM`), `permissionsOf`, `isTruncated`, `tenantOf`, `decodeEntitlementClaim`, `permissionCapOf` and the `isUserSession`, `isApiKeySession` and `isSessionSnapshot` guards, so client code and authorization adapters read the token without importing the server.
