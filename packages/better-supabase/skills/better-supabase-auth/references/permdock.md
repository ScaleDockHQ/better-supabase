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
  `member_<scope>_ids` helpers and doesn't add `tenant`. The scope is the
  manifest's root scope (the `rls.scopes` entry without `within`); set
  `entitlements.permdock: { scope }` in `better-supabase.config.ts` for
  another one.
- Name the same tenant claim on both sides. A non-default `claims.tenant` in
  `better-supabase.config.ts` must also be PermDock's `rls.tenantClaim` and
  go to `subjectFromSupabase` or `subjectFromSupabaseSession` as `{ tenant }`.
- Validate claims with PermDock's schema: `betterSupabase.claims(supabaseClaims().extend(appClaims))`.
- The helpers live in PermDock's `rls.schema` (`permdock` by default). Buckets
  and topics in `permdock` mode call them in `permdock` unless their `schema`
  option names another schema; it must equal `rls.schema`.
- Use the scope names the manifest declares (`organization`, not PermDock's
  `tenant` alias): the helpers are named after them, and doctor reports a
  key checked at another scope than its catalog entry.
- The entitlements module needs PermDock's hook to fill `claims.features`
  from `better_supabase.feature_claims`
  (`supabase.hook.claims: { features: 'better_supabase.feature_claims' }`).
- The `permdock` policy mode checks role and scope only. Use it only for
  permissions whose `rowConditions` is `false` in `permissions.catalog.json`.
  A missing flag or a key the catalog doesn't list is unknown and refused;
  regenerate the catalog with a current `permdock catalog`.
  Leave permissions with row conditions to the policies
  `permdock rls generate` writes; doctor reports BS214 and `permdock doctor`
  PD037 otherwise.
- `permdock` mode compares ids as text, so a path or topic segment must be
  the id's lowercase form.
- In MCP servers, narrow `tool.meta` with PermDock's `isPermission`, answer
  `visible` with `mayUse` and `authorize` with `can`. A tool without a
  PermDock permission in `meta` is denied: `visible` returns `false` and
  `authorize` returns `{ allowed: false }`. Use `decide` instead of `can` to
  put the denial reason in the refusal. `can` decides without a row, so check
  row-conditioned permissions inside `run` or rely on RLS.
- In Next.js, cache the permission snapshot in a `'use cache: private'`
  loader. The user id and the snapshot only exist after `bs.cached()`
  returns, so pass it the static tags only, then tag and time the entry from
  inside the loader with Next.js's `cacheTag` and `cacheLife`:

  ```ts
  import { cacheLife, cacheTag } from "next/cache";
  import { snapshotFor } from "permdock";
  import { cacheLifeFor, snapshotTag } from "permdock/next";
  import { subjectFromSupabaseSession } from "permdock/supabase";

  export async function loadSnapshot(orgId: string) {
    "use cache: private";
    const { session } = await bs.cached({ tags: [`org:${orgId}`] });
    const snapshot = snapshotFor(policy, subjectFromSupabaseSession(session), {
      tenant: orgId,
    });
    if (session.kind === "user") cacheTag(snapshotTag(session.user.id));
    cacheLife(cacheLifeFor(snapshot));
    return snapshot;
  }
  ```

  `bs.cached()` already caps the stale time at the token's expiry, and Next.js
  keeps the smaller `stale` of the two `cacheLife` calls. When a role or plan
  changes, drop the user's entries and the snapshot with
  `bs.invalidateSession(userId, { tags: [snapshotTag(userId)] })`.

- Doctor BS405 measures `memberships` plus `attrs` against PermDock's 1 KB
  budget and the whole token against 2 KB; run `doctor --as <user id>`.

Docs: https://bettersupabase.com/docs/auth/permdock.md
