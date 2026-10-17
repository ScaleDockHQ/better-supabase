import type { EntitlementPlansSource } from "../../config/index.ts";
import type { ClaimsMeta } from "../../schema/types.ts";
import type { ModuleLayout, ModuleDefinition } from "../module-types.ts";

import { DEFAULT_CLAIMS } from "../../core/claims.ts";
import { sqlIdent, sqlString } from "../../core/template.ts";
import { quotedTable, SCHEMA } from "../shared.ts";
import {
  booleanEntitlementValue,
  memberships,
  providerEntitlementChecks,
  tenantEntitlementChecks,
} from "./entitlements-checks.ts";
import { customerSource, entitlementsSource } from "./entitlements-source.ts";

const entitlementsSql = (
  claims: ClaimsMeta,
  layout: ModuleLayout = {},
): string => {
  const m = memberships(layout);
  const id = layout.entitlementsProvider?.idType ?? m.idType;
  const source = layout.entitlements?.source ?? "stripe-sync";

  if (source === "custom") {
    return `${SCHEMA}
grant usage on schema better_supabase to supabase_auth_admin;

-- entitlements.source is "custom": your better_supabase.tenant_entitlements(tenant ${id})
-- returns the tenant's feature keys (text[]) and your
-- better_supabase.tenant_entitlement_value(tenant ${id}, key text) a feature's
-- value (jsonb); the checks below call them.
set check_function_bodies = off;
${layout.entitlementsProvider ? providerEntitlementChecks(claims, layout.entitlementsProvider, layout.entitlements?.claim) : tenantEntitlementChecks(claims, m, layout.entitlements?.claim)}

revoke execute on function better_supabase.feature_claims(uuid) from public, anon, authenticated;
grant execute on function better_supabase.feature_claims(uuid) to service_role, supabase_auth_admin;
reset check_function_bodies;`;
  }

  if (typeof source === "object") {
    return `${SCHEMA}
grant usage on schema better_supabase to supabase_auth_admin;
${planEntitlements(source.plans, id)}
${layout.entitlementsProvider ? providerEntitlementChecks(claims, layout.entitlementsProvider, layout.entitlements?.claim) : tenantEntitlementChecks(claims, m, layout.entitlements?.claim)}

revoke execute on function better_supabase.feature_claims(uuid) from public, anon, authenticated;
grant execute on function better_supabase.feature_claims(uuid) to service_role, supabase_auth_admin;`;
  }

  return `${SCHEMA}
grant usage on schema better_supabase to supabase_auth_admin;

-- Lookup keys of the tenant's active entitlements, from the Stripe Sync
-- Engine's stripe.active_entitlements. Empty before the engine is installed.
create or replace function better_supabase.tenant_entitlements(tenant ${id})
returns text[]
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  customer_id text := better_supabase.tenant_stripe_customer(tenant);
begin
  if customer_id is null or to_regclass('stripe.active_entitlements') is null then
    return '{}';
  end if;
  return coalesce((
    select array_agg(distinct e.lookup_key order by e.lookup_key)
    from stripe.active_entitlements e
    where e.customer = customer_id
      and e.lookup_key is not null
  ), '{}');
end
$$;

revoke execute on function better_supabase.tenant_entitlements(${id}) from public, anon, authenticated;
grant execute on function better_supabase.tenant_entitlements(${id}) to service_role, supabase_auth_admin;
${booleanEntitlementValue(id)}
${layout.entitlementsProvider ? providerEntitlementChecks(claims, layout.entitlementsProvider, layout.entitlements?.claim) : tenantEntitlementChecks(claims, m, layout.entitlements?.claim)}

revoke execute on function better_supabase.feature_claims(uuid) from public, anon, authenticated;
grant execute on function better_supabase.feature_claims(uuid) to service_role, supabase_auth_admin;`;
};

const qualified = (table: string): string => quotedTable(table);

/** `tenant_entitlements` over a plan catalog: the active subscription's plan features. */
function planEntitlements(
  plans: EntitlementPlansSource["plans"],
  id: string,
): string {
  const subs = plans.subscriptions;
  const features = plans.features;
  const active = subs.activeStatuses ?? ["active", "trialing"];

  const status = subs.status
    ? `\n      and s.${sqlIdent(subs.status)}::text = any (array[${active.map(sqlString).join(", ")}]::text[])`
    : "";

  const included = features.included
    ? `\n      and f.${sqlIdent(features.included)}`
    : "";

  return `
-- Feature keys of the tenant's active plan (entitlements.source.plans):
-- ${subs.table} gives the plan, ${features.table} its features.
create or replace function better_supabase.tenant_entitlements(tenant ${id})
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(distinct f.${sqlIdent(features.feature)}::text order by f.${sqlIdent(features.feature)}::text), '{}')
    from ${qualified(subs.table)} s
    join ${qualified(features.table)} f on f.${sqlIdent(features.plan)}::text = s.${sqlIdent(subs.plan)}::text
    where s.${sqlIdent(subs.tenant)} = tenant_entitlements.tenant${status}${included}
      and f.${sqlIdent(features.feature)} is not null
$$;

revoke execute on function better_supabase.tenant_entitlements(${id}) from public, anon, authenticated;
grant execute on function better_supabase.tenant_entitlements(${id}) to service_role, supabase_auth_admin;
${planEntitlementValue(plans, id, status, included)}

-- The tenant's active plan keys, so other modules (usage quotas) can match a
-- plan by its key as well as by its features.
create or replace function better_supabase.tenant_plans(tenant ${id})
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(distinct s.${sqlIdent(subs.plan)}::text order by s.${sqlIdent(subs.plan)}::text), '{}')
    from ${qualified(subs.table)} s
    where s.${sqlIdent(subs.tenant)} = tenant_plans.tenant${status}
      and s.${sqlIdent(subs.plan)} is not null
$$;

revoke execute on function better_supabase.tenant_plans(${id}) from public, anon, authenticated;
grant execute on function better_supabase.tenant_plans(${id}) to service_role;`;
}

/** `tenant_entitlement_value` over the plan catalog, from `features.value` when set. */
function planEntitlementValue(
  plans: EntitlementPlansSource["plans"],
  id: string,
  status: string,
  included: string,
): string {
  const subs = plans.subscriptions;
  const features = plans.features;

  if (features.value === undefined) {
    return booleanEntitlementValue(id);
  }

  const value = `to_jsonb(f.${sqlIdent(features.value)})`;

  return `
-- The value of a feature for the tenant (entitlements.source.plans.features.value):
-- the largest number when several active plans set it, else the first
-- plan's value; true for a feature whose value is null, null without it.
create or replace function better_supabase.tenant_entitlement_value(tenant ${id}, key text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(${value}, 'true'::jsonb)
    from ${qualified(subs.table)} s
    join ${qualified(features.table)} f on f.${sqlIdent(features.plan)}::text = s.${sqlIdent(subs.plan)}::text
    where s.${sqlIdent(subs.tenant)} = tenant_entitlement_value.tenant${status}${included}
      and f.${sqlIdent(features.feature)}::text = tenant_entitlement_value.key
    order by case when jsonb_typeof(${value}) = 'number' then (${value} #>> '{}')::numeric end desc nulls last,
      s.${sqlIdent(subs.plan)}::text
    limit 1
$$;

revoke execute on function better_supabase.tenant_entitlement_value(${id}, text) from public, anon, authenticated;
grant execute on function better_supabase.tenant_entitlement_value(${id}, text) to service_role;`;
}

export const ENTITLEMENTS: ModuleDefinition = {
  name: "entitlements",
  scopes: ["tenant"],
  title: "Stripe entitlements",
  description:
    "Active Stripe entitlements per tenant from the Stripe Sync Engine, feature_claims() for the access token hook, and has_entitlement() and tenant_ids_with_entitlement() for RLS.",
  requires: ["tenant"],
  integrates: ["billing", "organizations"],
  providerRequires: [],
  target: "schema",
  build: (_ctx, layout) =>
    entitlementsSql(layout.claims ?? DEFAULT_CLAIMS, layout),
  extras: (ctx, layout) =>
    (layout.entitlements?.source ?? "stripe-sync") === "stripe-sync"
      ? entitlementsSource(customerSource(ctx, layout), layout)
      : "",
};
