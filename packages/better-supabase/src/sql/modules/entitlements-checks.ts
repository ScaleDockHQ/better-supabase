import type { ClaimsMeta } from "../../schema/types.ts";
import type { ModuleIdType } from "../context.ts";
import type {
  ModuleLayout,
  ModuleEntitlementsProvider,
} from "../module-types.ts";

import { fillTemplate } from "../../core/access-sql.ts";
import { sqlString } from "../../core/template.ts";
import { moduleContext } from "../module-context.ts";

/**
 * The tenant module's memberships table and columns, for the entitlement
 * lookups.
 */
interface Memberships {
  readonly table: string;
  readonly tenant: string;
  readonly user: string;
  readonly idType: ModuleIdType;
  /** The tenant module's `member_organization_ids` and `has_organization_role`. */
  readonly memberIds: string;
  readonly hasRole: string;
}

export function memberships(layout: ModuleLayout): Memberships {
  const ctx = moduleContext("tenant", layout);

  return {
    table: ctx.table("memberships"),
    tenant: ctx.col("memberships", "tenant"),
    user: ctx.col("memberships", "user"),
    idType: ctx.idType,
    memberIds: ctx.fn("member_organization_ids"),
    hasRole: ctx.fn("has_organization_role"),
  };
}

/** `entitlements.claim`: what `feature_claims` puts in the token. */
export type FeatureClaimOption =
  | false
  | {
      /** At most this many tenants, the lowest ids first. */
      readonly maxTenants?: number;
      /** Short codes written instead of the feature keys: `{ exports: "x" }`. */
      readonly keys?: Readonly<Record<string, string>>;
    };

/**
 * The body of `feature_claims` over `rows`, a query of (tenant text, keys
 * text[]) rows, shaped by `entitlements.claim`.
 */
function featureClaimsBody(
  rows: string,
  claim: FeatureClaimOption | undefined,
): string {
  if (claim === false) {
    return "  select '{}'::jsonb";
  }

  const max = claim?.maxTenants;

  if (max !== undefined && (!Number.isInteger(max) || max < 1)) {
    throw new TypeError(
      "entitlements.claim.maxTenants must be a positive integer",
    );
  }

  const keys = claim?.keys ?? {};

  const mapped =
    Object.keys(keys).length === 0
      ? "to_jsonb(r.keys)"
      : `to_jsonb(array(select coalesce(${sqlString(JSON.stringify(keys))}::jsonb ->> k, k) from unnest(r.keys) as k))`;

  return `  select coalesce(jsonb_object_agg(r.tenant, ${mapped}), '{}'::jsonb)
  from (
${rows}
    order by 1${max === undefined ? "" : `\n    limit ${String(max)}`}
  ) r`;
}

/** `entitlement_value`: a member's read of `tenant_entitlement_value`. */
const entitlementValueCheck = (id: string, member: string): string => `
-- The value of a feature for a member of the tenant: a number or text from
-- the plan catalog's value column, true for a feature without one, null
-- when the tenant lacks it or the caller is not a member.
create or replace function better_supabase.entitlement_value(tenant ${id}, key text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case when ${member} then better_supabase.tenant_entitlement_value(tenant, key) end
$$;

revoke execute on function better_supabase.entitlement_value(${id}, text) from public, anon;
grant execute on function better_supabase.entitlement_value(${id}, text) to authenticated, service_role;`;

/**
 * `tenant_entitlement_value` for sources without values: true when the tenant
 * has the key.
 */
export const booleanEntitlementValue = (id: string): string => `
-- The value of a feature for the tenant: true when it has the key, null
-- otherwise. Numeric limits come from the plan catalog's value column.
create or replace function better_supabase.tenant_entitlement_value(tenant ${id}, key text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case when key = any (better_supabase.tenant_entitlements(tenant)) then 'true'::jsonb end
$$;

revoke execute on function better_supabase.tenant_entitlement_value(${id}, text) from public, anon, authenticated;
grant execute on function better_supabase.tenant_entitlement_value(${id}, text) to service_role;`;

/**
 * The pieces of the entitlement lookups that differ between the tenant module
 * and a provider.
 */
interface ChecksSource {
  /** Comment lines before `has_entitlement`, with their own trailing blank line. */
  readonly intro: string;
  readonly idType: string;
  /** The `has_entitlement` body: the membership test and the key test. */
  readonly hasBody: string;
  /** The `entitlementValueCheck` membership expression. */
  readonly memberCheck: string;
  /** The `tenant_ids_with_entitlement` select. */
  readonly idsBody: string;
  /** The comment above `feature_claims`. */
  readonly claimsComment: string;
  /** The select `feature_claims` aggregates. */
  readonly claimsSelect: string;
}

const checksSql = (
  source: ChecksSource,
  claim: FeatureClaimOption | undefined,
): string => `
${source.intro}-- using ((select better_supabase.has_entitlement(organization_id, 'exports')))
create or replace function better_supabase.has_entitlement(tenant ${source.idType}, key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
${source.hasBody}
$$;

revoke execute on function better_supabase.has_entitlement(${source.idType}, text) from public, anon;
grant execute on function better_supabase.has_entitlement(${source.idType}, text) to authenticated, service_role;
${entitlementValueCheck(source.idType, source.memberCheck)}

-- Every tenant of the caller with \`key\`, for one set check per query instead of
-- one call per row:
--   using (organization_id in (select better_supabase.tenant_ids_with_entitlement('exports')))
create or replace function better_supabase.tenant_ids_with_entitlement(key text)
returns setof ${source.idType}
language sql
rows 1
stable
security definer
set search_path = ''
as $$
${source.idsBody}
$$;

revoke execute on function better_supabase.tenant_ids_with_entitlement(text) from public, anon;
grant execute on function better_supabase.tenant_ids_with_entitlement(text) to authenticated, service_role;

${source.claimsComment}
create or replace function better_supabase.feature_claims(user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
${featureClaimsBody(source.claimsSelect, claim)}
$$;`;

export const tenantEntitlementChecks = (
  claims: ClaimsMeta,
  m: Memberships,
  claim?: FeatureClaimOption,
): string =>
  checksSql(
    {
      intro: "",
      idType: m.idType,
      hasBody: `  select ${m.hasRole}(tenant)
    and key = any (better_supabase.tenant_entitlements(tenant))`,
      memberCheck: `${m.hasRole}(tenant)`,
      idsBody: `  select t.id from ${m.memberIds}() as t(id)
  where key = any (better_supabase.tenant_entitlements(t.id))`,
      claimsComment: `-- The \`${claims.features}\` claim: { [tenant id]: lookup keys }, read by
-- hasEntitlement(). Tenants without entitlements are left out. Call it from
-- your custom access token hook:
--   return jsonb_set(event, '{claims,${claims.features}}',
--     better_supabase.feature_claims((event ->> 'user_id')::uuid));`,
      claimsSelect: `    select m.${m.tenant}::text as tenant, e.keys
    from ${m.table} m
    cross join lateral (select better_supabase.tenant_entitlements(m.${m.tenant}) as keys) e
    where m.${m.user} = feature_claims.user_id
      and cardinality(e.keys) > 0`,
    },
    claim,
  );

/**
 * `has_entitlement` and `feature_claims` on the provider's `memberIds` and
 * `memberIdsFor`.
 */
export const providerEntitlementChecks = (
  claims: ClaimsMeta,
  provider: ModuleEntitlementsProvider,
  claim?: FeatureClaimOption,
): string => {
  const member = fillTemplate(
    "authorization.functions.memberIds",
    provider.memberIds,
    { scope: provider.scope },
  );

  const memberFor = fillTemplate(
    "authorization.functions.memberIdsFor",
    provider.memberIdsFor,
    { scope: provider.scope, user: "feature_claims.user_id" },
  );

  const id = provider.idType;
  const members = `tenant::text in (select t.id::text from ${member} as t(id))`;

  return checksSql(
    {
      intro: `-- Memberships come from the authorization provider (${provider.name}), in its
-- ${provider.scope} scope: authorization.functions.memberIds and memberIdsFor.

`,
      idType: id,
      hasBody: `  select ${members}
    and key = any (better_supabase.tenant_entitlements(tenant))`,
      memberCheck: members,
      idsBody: `  select t.id::${id} from ${member} as t(id)
  where key = any (better_supabase.tenant_entitlements(t.id::${id}))`,
      claimsComment: `-- The \`${claims.features}\` claim: { [${provider.scope} id]: lookup keys }, read by
-- hasEntitlement(). Register it with the provider's access token hook, which
-- runs as supabase_auth_admin, so that role needs execute on what
-- memberIdsFor calls.`,
      claimsSelect: `    select t.id::text as tenant, e.keys
    from ${memberFor} as t(id)
    cross join lateral (select better_supabase.tenant_entitlements(t.id::${id}) as keys) e
    where cardinality(e.keys) > 0`,
    },
    claim,
  );
};
