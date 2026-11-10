---
"better-supabase": patch
---

The provider contract stays additive at API version 1. A provider that still sets `functions.canApprove` or `approvals.distinctApprover` loads, and doctor notes that both are ignored. Doctor also reports a template placeholder the function does not take, including `approverFor` and `managedUsers`, which no module reads yet.

`Bootstrap.teamIdsTruncated` follows the provider's `teamIdsTruncatedClaim`, then the sessions hook option. A compact permissions bitset still decodes after Postgres wraps the base64. `claimFormat: "summary"` keeps every role when `roles.many` is on: each tenant is a sorted array of indexes. A provider `suspension.user` may be a column name, and its `userKey` applies only when that user setting is the one in use.

A cached JWKS is served for `maxStaleSeconds` after `cacheSeconds` (the same length by default) and then the request waits. A Supabase key set stays within 600 seconds. A former permission key throws `FormerPermissionKeyError` (`code: "former_permission_key"`), and doctor reports it instead of stopping.
