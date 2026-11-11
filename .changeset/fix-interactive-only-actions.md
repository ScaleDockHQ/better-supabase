---
"better-supabase": patch
---

Security: ownership transfer, organization deletion, impersonation start, platform invitations and SSO management are now interactive-only. `cap_allows` refuses their permission keys to an API key, an OAuth client and an agent or other `act` chain, whatever the token's scopes, and `can_assign` refuses the organization owner role to the same callers. `create_api_key` refuses an interactive-only key as a scope with `API_KEY_FORBIDDEN`, and existing keys that carry one get nothing from it. Add keys with `blocks.permissions.interactiveOnly` or `authorization.delegation.interactiveOnly`. An API key, OAuth client or agent that creates or rotates a key may only give it scopes the token holds itself. Run `better-supabase upgrade` to regenerate the `permissions` and `api-keys` modules.
