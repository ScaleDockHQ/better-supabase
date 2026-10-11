import type { EntitlementPlansSource } from "../../config/index.ts";
import type { ModuleLayout } from "../module-types.ts";
import type { ModuleEntitlementsProvider } from "../module-types.ts";
import type { FeatureClaimOption } from "./entitlements-checks.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { moduleContext } from "../module-context.ts";
import { splitTable } from "../shared.ts";
import { memberships } from "./entitlements-checks.ts";

/** The table holding each tenant's Stripe customer id. */
export interface EntitlementsSource {
  /** `table` or `schema.table`; unset uses the `organizations` module's. */
  readonly table?: string;
  /** Column with the Stripe customer id (`cus_...`). */
  readonly column?: string;
  /** Column with the tenant id. */
  readonly key: string;
  /** Where entitlements come from; the customer lookups are for `stripe-sync` only. */
  readonly source?: "stripe-sync" | "custom" | EntitlementPlansSource;
  readonly claim?: FeatureClaimOption;
}

/** A jsonb column and the JSON Schema its values must match. */
/** Users with a membership in a tenant of `customer`, from the provider's membership tables. */
function providerEntitlementMembers(
  provider: ModuleEntitlementsProvider,
): string {
  const sources = provider.memberships.flatMap((source) => {
    const scoped =
      "value" in source.scope
        ? source.scope.value === provider.scope
          ? ""
          : undefined
        : `\n    and m.${sqlIdent(source.scope.column)}::text = ${sqlString(provider.scope)}`;
    if (scoped === undefined) return [];
    const [schema, table] = splitTable(source.table);
    return [
      `  select distinct m.${sqlIdent(source.userColumn)}::uuid
  from ${sqlIdent(schema)}.${sqlIdent(table)} m
  where m.${sqlIdent(source.idColumn)}::text in (select t::text from better_supabase.stripe_customer_tenants(customer) t)${scoped}`,
    ];
  });
  return sources.length > 0
    ? sources.join("\n  union\n")
    : "  select null::uuid where false";
}

/**
 * `config.entitlements.customer`, or the `stripe_customer_id` column the
 * managed `organizations` module adds when both modules are installed.
 */
export function customerSource(
  layout: ModuleLayout,
  installed: readonly string[],
): Required<Omit<EntitlementsSource, "source" | "claim">> & {
  readonly deferred: boolean;
} {
  const configured = layout.entitlements;
  if (configured?.table !== undefined && configured.column !== undefined) {
    return {
      table: configured.table,
      column: configured.column,
      key: configured.key,
      deferred: false,
    };
  }
  if (
    installed.includes("billing") &&
    moduleContext("billing", layout, installed).manages
  ) {
    const customers = moduleContext("billing", layout, installed).tableName(
      "customers",
    );
    return {
      table: `${customers.schema}.${customers.name}`,
      column: "stripe_customer_id",
      key: "organization_id",
      deferred: true,
    };
  }
  if (
    installed.includes("organizations") &&
    moduleContext("organizations", layout, installed).manages
  ) {
    return {
      table: "better_supabase.organizations",
      column: "stripe_customer_id",
      key: "id",
      deferred: true,
    };
  }
  throw new TypeError(
    "The entitlements module needs entitlements.customer: the table.column with each tenant's Stripe customer id. With the managed organizations module it defaults to better_supabase.organizations.stripe_customer_id.",
  );
}

export function entitlementsSource(
  source: Required<Omit<EntitlementsSource, "source" | "claim">> & {
    readonly deferred: boolean;
  },
  layout: ModuleLayout,
): string {
  const provider = layout.entitlementsProvider;
  const m = memberships(layout);
  const [schema, table] = splitTable(source.table);
  const target = `${sqlIdent(schema)}.${sqlIdent(table)}`;
  const key = `t.${sqlIdent(source.key)}`;
  const column = `t.${sqlIdent(source.column)}`;
  const id = provider?.idType ?? m.idType;
  const definer =
    "language sql\nstable\nsecurity definer\nset search_path = ''";
  // plpgsql checks the body when it runs, which the organizations default
  // needs: that module's file adds the column and is applied after this one.
  // language sql checks the body now, so a missing configured column fails
  // the file instead of every request.
  const lookups = source.deferred
    ? `create or replace function better_supabase.tenant_stripe_customer(tenant ${id})
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return (select ${column} from ${target} t where ${key} = tenant);
end
$$;

create or replace function better_supabase.stripe_customer_tenants(customer text)
returns setof ${id}
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return query select ${key} from ${target} t where ${column} = customer;
end
$$;`
    : `create or replace function better_supabase.tenant_stripe_customer(tenant ${id})
returns text
${definer}
as $$
  select ${column} from ${target} t where ${key} = tenant
$$;

create or replace function better_supabase.stripe_customer_tenants(customer text)
returns setof ${id}
${definer}
as $$
  select ${key} from ${target} t where ${column} = customer
$$;`;
  return `
-- config.entitlements: ${source.table}.${source.column}
${lookups}

-- Users whose features claim carries the customer's entitlements, for
-- invalidating their sessions after entitlements.active_entitlement_summary.updated.
create or replace function better_supabase.entitlement_members(customer text)
returns setof uuid
${definer}
as $$
${
  provider
    ? providerEntitlementMembers(provider)
    : `  select distinct m.${m.user}
  from ${m.table} m
  where m.${m.tenant} in (select better_supabase.stripe_customer_tenants(customer))`
}
$$;

revoke execute on function better_supabase.tenant_stripe_customer(${id}) from public, anon, authenticated;
revoke execute on function better_supabase.stripe_customer_tenants(text) from public, anon, authenticated;
revoke execute on function better_supabase.entitlement_members(text) from public, anon, authenticated;
grant execute on function better_supabase.entitlement_members(text) to service_role;
`;
}
