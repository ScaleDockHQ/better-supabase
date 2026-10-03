# better-supabase next to PermDock

PermDock handles authorization and better-supabase handles tokens and data.
They share one access token hook and one claim contract, and neither imports
the other.

## Who owns what

| Area                 | better-supabase                                             | PermDock                                                                               |
| -------------------- | ----------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| Access token hook    | none                                                        | `permdock supabase hook generate`, the only hook                                       |
| Claims               | `features`, through `supabase.hook.claims`                  | `user_role`, `roles`, `memberships`, the tenant claim, `attrs`, `authz_ver`            |
| SQL helpers          | the SQL kit (`better_supabase.*`)                           | `permdock rls generate`: `permdock_has`, `permitted_<scope>_ids`, `member_<scope>_ids` |
| Storage and Realtime | `defineBucket`, `defineTopic` with a `permdock` policy mode | the helpers those policies call                                                        |
| MCP                  | `createMcp` with `authorize` and `visible`                  | the permissions in each tool's `meta`                                                  |

## Rules

- Don't run `better-supabase sql add tenant` (it stops without `--force`),
  don't call `membership_claims()` from a hook, and don't write `roles`,
  `user_role`, `memberships` or the tenant claim yourself. Doctor reports
  BS407 when a hook does.
- `sql add entitlements` is fine: `features` is not a PermDock claim. Add
  `claims: { features: 'better_supabase.feature_claims' }` to `supabase.hook`
  in `permdock.config.ts`, run `permdock supabase hook generate`, and
  `hasEntitlement(session, ...)` works.
- Run `permdock supabase inspect --out` before `sql add entitlements`. With
  `permdock.manifest.json` present, the module reads PermDock's
  `member_<scope>_ids` helpers and doesn't add `tenant`. Set
  `entitlements.permdock: { scope }` in `better-supabase.config.ts` for a
  scope other than `organization`.
- Name the same tenant claim on both sides. A non-default `claims.tenant` in
  `better-supabase.config.ts` must also be PermDock's `rls.tenantClaim` and
  go to `subjectFromSupabase` or `subjectFromSupabaseSession` as `{ tenant }`.
- Validate claims with PermDock's schema: `sb.claims(supabaseClaims().extend(appClaims))`.
- The helpers live in PermDock's `rls.schema`, which must equal the `schema`
  option of buckets and topics in `permdock` mode.
- The `permdock` policy mode checks role and scope only. Use it only for
  permissions whose `rowConditions` is `false` in `permissions.catalog.json`.
  Leave permissions with row conditions to the policies
  `permdock rls generate` writes; doctor reports BS214 and `permdock doctor`
  PD037 otherwise.
- `permdock` mode compares ids as text, so a path or topic segment must be
  the id's lowercase form.
- In MCP servers, narrow `tool.meta` with PermDock's `isPermission`, answer
  `visible` with `mayUse` and `authorize` with `can`. `can` decides without
  a row, so check row-conditioned permissions inside `run` or rely on RLS.
- In Next.js, cache the permission snapshot with
  `next.cached({ tags: [snapshotTag(userId)], life: cacheLifeFor(snapshot) })`
  and drop it with `next.invalidateSession(userId, { tags: [snapshotTag(userId)] })`
  when a role or plan changes.
- Doctor BS405 measures `memberships` plus `attrs` against PermDock's 1 KB
  budget and the whole token against 2 KB; run `doctor --as <user id>`.

Docs: https://bettersupabase.com/docs/auth/permdock.md
