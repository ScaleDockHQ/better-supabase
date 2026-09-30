---
'better-supabase': minor
---

Align with PermDock's authorization contract, so a project can use better-supabase and PermDock on the same claims. The migration guide at https://bettersupabase.com/docs/migration/0.1-to-0.2 lists every step.

Breaking changes:

- The active tenant claim is `tenant_id` instead of `org_id`, in the token and in `app_metadata`. The new `claims` block in `better-supabase.config.ts` (`claims: { tenant, scope, features }`) renames it for the tenant plugin, the SQL kit, storage and realtime at once. `plugins.tenant.claim` is removed.
- SQL kit: `better_supabase.current_org_id()` is now `current_tenant_id()`. `membership_claims()` moves to the tenant module and returns PermDock's `[{ scope, id, roles }]`. Plan features move out of memberships into `feature_claims()` in the entitlements module, which fills the `features` claim (`{ [tenantId]: string[] }`).
- `MembershipClaim` has PermDock's shape (`scope`, `id`, `roles`, and optional `within`, `via`, `expiresAt`). `hasEntitlement` and `EntitlementKey` read the `features` claim.
- `asUser` signs ES256 tokens with the key from `better-supabase keys` (`signing_keys_path` in `supabase/config.toml`), like a hosted project. `{ alg: 'HS256' }` keeps the shared secret and only works against a local stack.
- `SPEC_PINS.mcp` and `MCP_PROTOCOL_VERSION` are `2026-07-28`. `createMcp` serves stateless requests (`server/discover`, request `_meta`, `Mcp-Method` and `Mcp-Name` headers) and still answers `initialize` for `2025-11-25`, `2025-06-18` and `2025-03-26` clients. A 403 carries an `insufficient_scope` challenge.
- BS405 measures the whole token against 2 KB and, when the project has a `permdock.config.ts`, `memberships` plus `attrs` against PermDock's 1 KB budget (`doctor.claimsLimit` overrides the budget, or the whole-token limit without PermDock).

New:

- `sb.userMetadata(schema)` parses `user_metadata` into a typed `session.profile` for display. Metadata that fails the schema leaves `profile` undefined and logs one warning with the failing paths. No authorization code reads it. `ProfileOf<B>` in `better-supabase/react` types `useSession` from `createHooks`.
- Buckets take a PermDock policy (`{ permdock: { read, write }, scope }`) and topics a `permdock: { receive, send, scope }` option. The generated policies check PermDock permissions through its `permitted_<scope>_ids()` or `permdock_has()` helpers instead of the tenant claim.
- `sql add tenant` stops when a `permdock.config.ts` exists, unless you pass `--force`. Doctor BS407 reports a hook that calls `membership_claims` or writes PermDock's claims next to PermDock.
- `better-supabase/testing` exports `signLocalJwt`, `localSigningKey`, `signTestJwtWithKey` and the `SigningJwk` type.
- A new docs page, https://bettersupabase.com/docs/auth/permdock, shows both packages in one project.
