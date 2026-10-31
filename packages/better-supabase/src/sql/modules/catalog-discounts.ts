import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";
import type { ImportTargetContribution } from "../contributions.ts";
import type { Names } from "./catalog-names.ts";

import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { fail, lockTable, serviceGrant, userGrant } from "../shared.ts";
import { guard } from "./catalog-functions.ts";
import { supplyImportTargets } from "./catalog-supply.ts";

/** What a discount group groups: customers or products. */
const DISCOUNT_GROUP_KINDS = ["customer", "product"] as const;

/** The discount tables' entries in the catalog's name registry. */
export const DISCOUNT_ENTITIES = {
  discountGroups: {
    name: "discount_groups",
    lifecycle: { tenant: "tenant", export: true },
    optionalTable: true,
    app: { onlyWhenMapped: true },
    columns: {
      id: "id",
      tenant: "tenant_id",
      kind: "kind",
      code: "code",
      name: "name",
      createdAt: "created_at",
      updatedAt: "updated_at",
    },
  },
  discountGroupParties: {
    name: "discount_group_parties",
    lifecycle: { tenant: "tenant", export: true },
    optionalTable: true,
    app: { onlyWhenMapped: true },
    columns: {
      tenant: "tenant_id",
      group: "group_id",
      party: "party_id",
      createdAt: "created_at",
    },
  },
  discountRules: {
    name: "discount_rules",
    lifecycle: { tenant: "tenant", export: true },
    optionalTable: true,
    app: { onlyWhenMapped: true },
    columns: {
      id: "id",
      tenant: "tenant_id",
      customerGroup: "customer_group_id",
      productGroup: "product_group_id",
      validFrom: "valid_from",
      validTo: "valid_to",
      minQuantity: "min_quantity",
      discountBps: "discount_bps",
      fixedPrice: "fixed_price",
      currency: "currency",
      createdAt: "created_at",
      updatedAt: "updated_at",
    },
  },
} as const;

const NO_GROUP = "'00000000-0000-4000-8000-000000000000'::uuid";

const KINDS = DISCOUNT_GROUP_KINDS.map((kind) => `'${kind}'`).join(", ");

/**
 * Whether a table added in version 6 exists: always when managed, and when the
 * app maps it on an adopted catalog.
 */
function discountTable(ctx: BlockSqlContext, table: string): boolean {
  return ctx.hasTable(table) && (ctx.manages || !ctx.owns(table));
}

/** Whether the catalog has the discount tables (groups, members and rules). */
function discountsOn(ctx: BlockSqlContext): boolean {
  return (
    discountTable(ctx, "discountGroups") &&
    discountTable(ctx, "discountGroupParties") &&
    discountTable(ctx, "discountRules")
  );
}

function readPolicy(ctx: BlockSqlContext, names: Names, table: string): string {
  const t = ctx.table(table);

  return renderPolicy(
    makePolicy({
      table: t,
      name: `${ctx.tableName(table).name}_read`,
      command: "select",
      roles: ["authenticated"],
      using: `${ctx.col(table, "tenant")} in (select ${ctx.scope.ids(names.read)})`,
    }),
    { drop: true, target: t },
  );
}

/** The discount group column version 6 adds to variants (managed mode). */
export function discountColumns(ctx: BlockSqlContext): string {
  if (
    !ctx.manages ||
    !discountsOn(ctx) ||
    !ctx.has("variants", "discountGroup")
  ) {
    return "";
  }

  const column = ctx.col("variants", "discountGroup");

  return `
-- The product group a variant belongs to for the discount matrix.
alter table ${ctx.table("variants")} add column if not exists ${column} uuid references ${ctx.table("discountGroups")} (${ctx.col("discountGroups", "id")}) on delete set null;
create index if not exists ${ctx.naming.rename("product_variants_discount_group_idx")} on ${ctx.table("variants")} (${column}) where ${column} is not null;`;
}

/** The discount group, member and rule tables (managed mode). */
export function discountTables(ctx: BlockSqlContext, names: Names): string {
  if (!ctx.manages || !discountsOn(ctx)) {
    return "";
  }

  const t = (name: string): string => ctx.table(name);
  const g = (column: string): string => ctx.col("discountGroups", column);
  const m = (column: string): string => ctx.col("discountGroupParties", column);
  const r = (column: string): string => ctx.col("discountRules", column);

  return `
-- Customer groups and product groups. A rule of the matrix pairs one of each.
create table if not exists ${t("discountGroups")} (
  ${g("id")} uuid primary key default gen_random_uuid(),
  ${g("tenant")} ${ctx.idType} not null,
  ${g("kind")} text not null check (${g("kind")} in (${KINDS})),
  ${g("code")} text not null check (length(${g("code")}) between 1 and 50),
  ${g("name")} text not null check (length(${g("name")}) between 1 and 200),
  ${g("createdAt")} timestamptz not null default now(),
  ${g("updatedAt")} timestamptz not null default now(),
  unique (${g("tenant")}, ${g("kind")}, ${g("code")})
);
${lockTable(t("discountGroups"), { read: true })}
${readPolicy(ctx, names, "discountGroups")}

-- The customers of a customer group; a party is in one group.
create table if not exists ${t("discountGroupParties")} (
  ${m("tenant")} ${ctx.idType} not null,
  ${m("group")} uuid not null references ${t("discountGroups")} (${g("id")}) on delete cascade,
  ${m("party")} text not null check (length(${m("party")}) between 1 and 200),
  ${m("createdAt")} timestamptz not null default now(),
  primary key (${m("tenant")}, ${m("party")})
);
create index if not exists ${ctx.naming.rename("discount_group_parties_group_idx")} on ${t("discountGroupParties")} (${m("group")});
${lockTable(t("discountGroupParties"), { read: true })}
${readPolicy(ctx, names, "discountGroupParties")}

-- The discount matrix. A rule without a customer group or without a product
-- group applies to every customer or product; a quantity break is another rule
-- with a higher min_quantity. A fixed price replaces the unit amount, in its
-- currency; the discount still applies to it.
create table if not exists ${t("discountRules")} (
  ${r("id")} uuid primary key default gen_random_uuid(),
  ${r("tenant")} ${ctx.idType} not null,
  ${r("customerGroup")} uuid references ${t("discountGroups")} (${g("id")}) on delete restrict,
  ${r("productGroup")} uuid references ${t("discountGroups")} (${g("id")}) on delete restrict,
  ${r("validFrom")} date,
  ${r("validTo")} date,
  ${r("minQuantity")} numeric(18, 4) not null default 0 check (${r("minQuantity")} >= 0),
  ${r("discountBps")} integer not null default 0 check (${r("discountBps")} >= 0 and ${r("discountBps")} <= 10000),
  ${r("fixedPrice")} bigint check (${r("fixedPrice")} >= 0),
  ${r("currency")} char(3) check (${r("currency")} ~ '^[A-Z]{3}$'),
  ${r("createdAt")} timestamptz not null default now(),
  ${r("updatedAt")} timestamptz not null default now(),
  check (${r("validTo")} is null or ${r("validFrom")} is null or ${r("validTo")} >= ${r("validFrom")}),
  check ((${r("fixedPrice")} is null) = (${r("currency")} is null))
);
create unique index if not exists ${ctx.naming.rename("discount_rules_key")} on ${t("discountRules")} (${r("tenant")}, coalesce(${r("customerGroup")}, ${NO_GROUP}), coalesce(${r("productGroup")}, ${NO_GROUP}), coalesce(${r("validFrom")}, date '0001-01-01'), ${r("minQuantity")});
create index if not exists ${ctx.naming.rename("discount_rules_customer_group_idx")} on ${t("discountRules")} (${r("customerGroup")}) where ${r("customerGroup")} is not null;
create index if not exists ${ctx.naming.rename("discount_rules_product_group_idx")} on ${t("discountRules")} (${r("productGroup")}) where ${r("productGroup")} is not null;
${lockTable(t("discountRules"), { read: true })}
${readPolicy(ctx, names, "discountRules")}
`;
}

/** The group a code or id names, as a `uuid` of the right kind and tenant. */
function groupLookup(
  ctx: BlockSqlContext,
  options: {
    readonly tenant: string;
    readonly id: string;
    readonly code: string;
    readonly kind: string;
  },
): string {
  const g = (column: string): string => ctx.col("discountGroups", column);

  return `(select y.${g("id")} from ${ctx.table("discountGroups")} y
      where y.${g("tenant")} = ${options.tenant} and y.${g("kind")} = ${options.kind}
        and ((${options.id} is not null and y.${g("id")} = ${options.id}) or (${options.id} is null and ${options.code} is not null and y.${g("code")} = ${options.code})))`;
}

function groupFunctions(ctx: BlockSqlContext, names: Names): string {
  const { fn } = names;
  const groups = ctx.table("discountGroups");
  const members = ctx.table("discountGroupParties");
  const rules = ctx.table("discountRules");
  const variants = ctx.table("variants");
  const g = (column: string): string => ctx.col("discountGroups", column);
  const m = (column: string): string => ctx.col("discountGroupParties", column);
  const r = (column: string): string => ctx.col("discountRules", column);
  const v = (column: string): string => ctx.col("variants", column);

  const variantGroup = ctx.has("variants", "discountGroup")
    ? `
-- Puts a variant in a product group, or takes it out with null.
create or replace function ${fn("set_variant_discount_group")}(variant uuid, "group" uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  select x.${v("tenant")} into v_tenant from ${variants} x where x.${v("id")} = set_variant_discount_group.variant;
  if v_tenant is null then
    ${fail("CATALOG_VARIANT_NOT_FOUND", "variant not found", "P0002")}
  end if;
  ${guard(names, "v_tenant", names.update)}
  if set_variant_discount_group."group" is not null and not exists (
    select 1 from ${groups} y where y.${g("id")} = set_variant_discount_group."group" and y.${g("tenant")} = v_tenant and y.${g("kind")} = 'product') then
    ${fail("CATALOG_DISCOUNT_GROUP_NOT_FOUND", "a variant takes a product group of its organization", "P0002")}
  end if;
  update ${variants} x set ${v("discountGroup")} = set_variant_discount_group."group", ${v("updatedAt")} = now() where x.${v("id")} = set_variant_discount_group.variant;
  return true;
end;
$$;
${userGrant(`${fn("set_variant_discount_group")}(uuid, uuid)`)}
`
    : "";

  const productGroupOf = ctx.has("variants", "discountGroup")
    ? `(select y.${v("discountGroup")} from ${variants} y where y.${v("id")} = $3 and y.${v("tenant")} = $1)`
    : "null::uuid";

  return `
-- Creates a discount group (group null) or renames one. kind is customer or
-- product and can't change; the code is unique per tenant and kind. Returns
-- its id and whether it was created.
create or replace function ${fn("save_discount_group")}(tenant ${ctx.idType}, "group" uuid, kind text, code text, name text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_created boolean := save_discount_group."group" is null;
  v_code text := btrim(save_discount_group.code);
begin
  ${guard(names, "save_discount_group.tenant")}
  if save_discount_group.kind is null or save_discount_group.kind not in (${KINDS}) then
    ${fail("CATALOG_DISCOUNT_GROUP_INVALID", "the kind is customer or product", "22023")}
  end if;
  if v_code is null or length(v_code) not between 1 and 50 or length(btrim(coalesce(save_discount_group.name, ''))) not between 1 and 200 then
    ${fail("CATALOG_DISCOUNT_GROUP_INVALID", "a group needs a code of up to 50 and a name of up to 200 characters", "22023")}
  end if;
  begin
    if v_created then
      insert into ${groups} as x (${g("tenant")}, ${g("kind")}, ${g("code")}, ${g("name")})
      values (save_discount_group.tenant, save_discount_group.kind, v_code, btrim(save_discount_group.name))
      returning x.${g("id")} into v_id;
    else
      update ${groups} x set ${g("code")} = v_code, ${g("name")} = btrim(save_discount_group.name), ${g("updatedAt")} = now()
      where x.${g("id")} = save_discount_group."group" and x.${g("tenant")} = save_discount_group.tenant and x.${g("kind")} = save_discount_group.kind
      returning x.${g("id")} into v_id;
      if v_id is null then
        ${fail("CATALOG_DISCOUNT_GROUP_NOT_FOUND", "discount group not found", "P0002")}
      end if;
    end if;
  exception when unique_violation then
    ${fail("CATALOG_DISCOUNT_GROUP_EXISTS", "a group of this kind already has this code", "23505")}
  end;
  return jsonb_build_object('id', v_id, 'created', v_created);
end;
$$;
${userGrant(`${fn("save_discount_group")}(${ctx.idType}, uuid, text, text, text)`)}

-- Deletes a group no rule uses. Its customers leave it and its variants lose
-- the group.
create or replace function ${fn("delete_discount_group")}("group" uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  select x.${g("tenant")} into v_tenant from ${groups} x where x.${g("id")} = delete_discount_group."group";
  if v_tenant is null then
    return false;
  end if;
  ${guard(names, "v_tenant")}
  if exists (select 1 from ${rules} y where y.${r("customerGroup")} = delete_discount_group."group" or y.${r("productGroup")} = delete_discount_group."group") then
    ${fail("CATALOG_DISCOUNT_GROUP_IN_USE", "a rule of the matrix still uses this group", "23503")}
  end if;
  delete from ${groups} x where x.${g("id")} = delete_discount_group."group";
  return true;
end;
$$;
${userGrant(`${fn("delete_discount_group")}(uuid)`)}

-- Puts a party (a company or person id) in a customer group, or takes it out
-- with null. A party is in one group; setting another moves it.
create or replace function ${fn("set_party_discount_group")}(tenant ${ctx.idType}, party text, "group" uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  ${guard(names, "set_party_discount_group.tenant")}
  if set_party_discount_group.party is null or length(btrim(set_party_discount_group.party)) not between 1 and 200 then
    ${fail("CATALOG_DISCOUNT_PARTY_INVALID", "name the party by its id", "22023")}
  end if;
  if set_party_discount_group."group" is null then
    delete from ${members} x where x.${m("tenant")} = set_party_discount_group.tenant and x.${m("party")} = btrim(set_party_discount_group.party);
    return true;
  end if;
  if not exists (select 1 from ${groups} y where y.${g("id")} = set_party_discount_group."group" and y.${g("tenant")} = set_party_discount_group.tenant and y.${g("kind")} = 'customer') then
    ${fail("CATALOG_DISCOUNT_GROUP_NOT_FOUND", "a party takes a customer group of its organization", "P0002")}
  end if;
  insert into ${members} as x (${m("tenant")}, ${m("group")}, ${m("party")})
  values (set_party_discount_group.tenant, set_party_discount_group."group", btrim(set_party_discount_group.party))
  on conflict (${m("tenant")}, ${m("party")}) do update set ${m("group")} = excluded.${m("group")};
  return true;
end;
$$;
${userGrant(`${fn("set_party_discount_group")}(${ctx.idType}, text, uuid)`)}
${variantGroup}
-- The checks of a rule's attributes, shared by the function and the import.
create or replace function ${fn("discount_rule_check")}(tenant ${ctx.idType}, attrs jsonb)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_customer uuid;
  v_product uuid;
begin
  begin
    v_customer := nullif(discount_rule_check.attrs ->> 'customerGroupId', '')::uuid;
    v_product := nullif(discount_rule_check.attrs ->> 'productGroupId', '')::uuid;
    perform (discount_rule_check.attrs ->> 'validFrom')::date, (discount_rule_check.attrs ->> 'validTo')::date;
  exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    ${fail("CATALOG_DISCOUNT_RULE_INVALID", "group ids are uuids and dates are YYYY-MM-DD", "22023")}
  end;
  if v_customer is not null and not exists (select 1 from ${groups} y where y.${g("id")} = v_customer and y.${g("tenant")} = discount_rule_check.tenant and y.${g("kind")} = 'customer') then
    ${fail("CATALOG_DISCOUNT_GROUP_NOT_FOUND", "customerGroupId isn't a customer group of this organization", "P0002")}
  end if;
  if v_product is not null and not exists (select 1 from ${groups} y where y.${g("id")} = v_product and y.${g("tenant")} = discount_rule_check.tenant and y.${g("kind")} = 'product') then
    ${fail("CATALOG_DISCOUNT_GROUP_NOT_FOUND", "productGroupId isn't a product group of this organization", "P0002")}
  end if;
  if coalesce(discount_rule_check.attrs ->> 'discountBps', '0') !~ '^[0-9]{1,5}$' or coalesce(discount_rule_check.attrs ->> 'discountBps', '0')::integer > 10000 then
    ${fail("CATALOG_DISCOUNT_RULE_INVALID", "discountBps is a whole number from 0 to 10000", "22023")}
  end if;
  if coalesce(discount_rule_check.attrs ->> 'minQuantity', '0') !~ '^[0-9]{1,14}([.][0-9]{1,4})?$' then
    ${fail("CATALOG_DISCOUNT_RULE_INVALID", "minQuantity is zero or more", "22023")}
  end if;
  if (discount_rule_check.attrs ->> 'fixedPrice') is not null and discount_rule_check.attrs ->> 'fixedPrice' !~ '^[0-9]{1,18}$' then
    ${fail("CATALOG_DISCOUNT_RULE_INVALID", "fixedPrice is a whole number of minor units", "22023")}
  end if;
  if ((discount_rule_check.attrs ->> 'fixedPrice') is null) <> ((discount_rule_check.attrs ->> 'currency') is null)
    or ((discount_rule_check.attrs ->> 'currency') is not null and (discount_rule_check.attrs ->> 'currency') !~ '^[A-Z]{3}$') then
    ${fail("CATALOG_DISCOUNT_RULE_INVALID", "a fixed price comes with its ISO 4217 currency, and neither without the other", "22023")}
  end if;
  if (discount_rule_check.attrs ->> 'validFrom') is not null and (discount_rule_check.attrs ->> 'validTo') is not null
    and (discount_rule_check.attrs ->> 'validTo')::date < (discount_rule_check.attrs ->> 'validFrom')::date then
    ${fail("CATALOG_DISCOUNT_RULE_INVALID", "validTo is on or after validFrom", "22023")}
  end if;
end;
$$;
revoke execute on function ${fn("discount_rule_check")}(${ctx.idType}, jsonb) from public, anon, authenticated;

-- Creates a rule of the discount matrix (rule null) or replaces one. attrs: {
-- customerGroupId?, productGroupId?, validFrom?, validTo?, minQuantity?,
-- discountBps?, fixedPrice? (minor units as text), currency? }. A rule with the
-- same groups, start date and minimum quantity is one rule: the call updates
-- it. Returns its id and whether it was created.
create or replace function ${fn("save_discount_rule")}(tenant ${ctx.idType}, rule uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_attrs jsonb := coalesce(save_discount_rule.attrs, '{}'::jsonb);
  v_id uuid;
  v_created boolean := true;
begin
  ${guard(names, "save_discount_rule.tenant")}
  perform ${fn("discount_rule_check")}(save_discount_rule.tenant, v_attrs);
  if save_discount_rule.rule is not null then
    update ${rules} x set
      ${r("customerGroup")} = nullif(v_attrs ->> 'customerGroupId', '')::uuid, ${r("productGroup")} = nullif(v_attrs ->> 'productGroupId', '')::uuid,
      ${r("validFrom")} = (v_attrs ->> 'validFrom')::date, ${r("validTo")} = (v_attrs ->> 'validTo')::date,
      ${r("minQuantity")} = coalesce((v_attrs ->> 'minQuantity')::numeric, 0), ${r("discountBps")} = coalesce((v_attrs ->> 'discountBps')::integer, 0),
      ${r("fixedPrice")} = (v_attrs ->> 'fixedPrice')::bigint, ${r("currency")} = v_attrs ->> 'currency', ${r("updatedAt")} = now()
    where x.${r("id")} = save_discount_rule.rule and x.${r("tenant")} = save_discount_rule.tenant
    returning x.${r("id")} into v_id;
    if v_id is null then
      ${fail("CATALOG_DISCOUNT_RULE_NOT_FOUND", "discount rule not found", "P0002")}
    end if;
    return jsonb_build_object('id', v_id, 'created', false);
  end if;
  insert into ${rules} as x (${r("tenant")}, ${r("customerGroup")}, ${r("productGroup")}, ${r("validFrom")}, ${r("validTo")}, ${r("minQuantity")}, ${r("discountBps")}, ${r("fixedPrice")}, ${r("currency")})
  values (save_discount_rule.tenant, nullif(v_attrs ->> 'customerGroupId', '')::uuid, nullif(v_attrs ->> 'productGroupId', '')::uuid,
    (v_attrs ->> 'validFrom')::date, (v_attrs ->> 'validTo')::date, coalesce((v_attrs ->> 'minQuantity')::numeric, 0),
    coalesce((v_attrs ->> 'discountBps')::integer, 0), (v_attrs ->> 'fixedPrice')::bigint, v_attrs ->> 'currency')
  on conflict (${r("tenant")}, coalesce(${r("customerGroup")}, ${NO_GROUP}), coalesce(${r("productGroup")}, ${NO_GROUP}), coalesce(${r("validFrom")}, date '0001-01-01'), ${r("minQuantity")}) do update set
    ${r("validTo")} = excluded.${r("validTo")}, ${r("discountBps")} = excluded.${r("discountBps")}, ${r("fixedPrice")} = excluded.${r("fixedPrice")},
    ${r("currency")} = excluded.${r("currency")}, ${r("updatedAt")} = now()
  returning x.${r("id")}, (xmax = 0) into v_id, v_created;
  return jsonb_build_object('id', v_id, 'created', v_created);
end;
$$;
${userGrant(`${fn("save_discount_rule")}(${ctx.idType}, uuid, jsonb)`)}

-- Deletes a rule of the matrix.
create or replace function ${fn("delete_discount_rule")}(rule uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  select x.${r("tenant")} into v_tenant from ${rules} x where x.${r("id")} = delete_discount_rule.rule;
  if v_tenant is null then
    return false;
  end if;
  ${guard(names, "v_tenant")}
  delete from ${rules} x where x.${r("id")} = delete_discount_rule.rule;
  return true;
end;
$$;
${userGrant(`${fn("delete_discount_rule")}(uuid)`)}

-- The discount a line gets: { discountBps, fixedPrice, currency, ruleId }.
-- party is the customer's id, product a catalog variant, quantity the line's
-- and on the date the document prices at. A rule applies when its customer
-- group is the party's (or it has none), its product group is the variant's
-- (or it has none), the date is inside its window and quantity reaches its
-- minimum. The most specific rule wins: both groups, then the customer group,
-- then the product group, then neither. Among rules equally specific the
-- highest quantity break wins, then the latest start date. With a currency, a
-- rule whose fixed price is in another currency is skipped. No rule gives a
-- discountBps of 0 and a null ruleId. It reads as the caller.
create or replace function ${fn("resolve_line_discount")}(tenant ${ctx.idType}, party text, product uuid, quantity numeric, "on" date, currency text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with scope as (
    select (select x.${m("group")} from ${members} x where x.${m("tenant")} = $1 and x.${m("party")} = $2) as customer_group,
      ${productGroupOf} as item_group
  ),
  matched as (
    select r.${r("id")} as id, r.${r("discountBps")} as discount_bps, r.${r("fixedPrice")} as fixed_price, r.${r("currency")} as currency
    from ${rules} r cross join scope s
    where r.${r("tenant")} = $1
      and (r.${r("customerGroup")} is null or r.${r("customerGroup")} = s.customer_group)
      and (r.${r("productGroup")} is null or r.${r("productGroup")} = s.item_group)
      and (r.${r("validFrom")} is null or r.${r("validFrom")} <= coalesce($5, current_date))
      and (r.${r("validTo")} is null or r.${r("validTo")} >= coalesce($5, current_date))
      and r.${r("minQuantity")} <= coalesce($4, 1)
      and (r.${r("fixedPrice")} is null or $6 is null or r.${r("currency")} = upper($6))
    order by (case when r.${r("customerGroup")} is not null then 2 else 0 end) + (case when r.${r("productGroup")} is not null then 1 else 0 end) desc,
      r.${r("minQuantity")} desc, r.${r("validFrom")} desc nulls last, r.${r("createdAt")}, r.${r("id")}
    limit 1
  )
  select coalesce((select jsonb_build_object('discountBps', m.discount_bps, 'fixedPrice', m.fixed_price::text, 'currency', m.currency, 'ruleId', m.id) from matched m),
    jsonb_build_object('discountBps', 0, 'fixedPrice', null, 'currency', null, 'ruleId', null))
$$;
${userGrant(`${fn("resolve_line_discount")}(${ctx.idType}, text, uuid, numeric, date, text)`)}
`;
}

function importFunctions(ctx: BlockSqlContext, names: Names): string {
  const { fn } = names;
  const groups = ctx.table("discountGroups");
  const members = ctx.table("discountGroupParties");
  const rules = ctx.table("discountRules");
  const g = (column: string): string => ctx.col("discountGroups", column);
  const m = (column: string): string => ctx.col("discountGroupParties", column);
  const r = (column: string): string => ctx.col("discountRules", column);

  const customerOf = groupLookup(ctx, {
    tenant: "v_tenant",
    id: "v_customer_id",
    code: "v_customer_code",
    kind: "'customer'",
  });

  const productOf = groupLookup(ctx, {
    tenant: "v_tenant",
    id: "v_product_id",
    code: "v_product_code",
    kind: "'product'",
  });

  return `
-- The import target of the discount_group entity: item.data is { kind, code,
-- name, parties? } where parties lists the ids of a customer group's members
-- and replaces them. A new key with a code the tenant already has for that kind
-- takes over that group.
create or replace function ${fn("import_discount_group")}(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType} := (import_discount_group.item ->> 'tenant')::${ctx.idType};
  v_data jsonb := import_discount_group.item -> 'data';
  v_kind text := v_data ->> 'kind';
  v_code text := btrim(v_data ->> 'code');
  v_name text := btrim(coalesce(v_data ->> 'name', v_data ->> 'code'));
  v_id uuid;
  v_updated timestamptz;
begin
  if v_kind is null or v_kind not in (${KINDS}) or v_code is null or length(v_code) not between 1 and 50 or length(v_name) not between 1 and 200 then
    ${fail("IMPORT_ITEM_INVALID", "a discount group needs a kind (customer or product), a code and a name", "22023")}
  end if;
  if v_data ? 'parties' and (v_kind <> 'customer' or jsonb_typeof(v_data -> 'parties') <> 'array') then
    ${fail("IMPORT_ITEM_INVALID", "parties is a list on a customer group", "22023")}
  end if;
  if import_discount_group.subject_id is null then
    insert into ${groups} as x (${g("tenant")}, ${g("kind")}, ${g("code")}, ${g("name")})
    values (v_tenant, v_kind, v_code, v_name)
    on conflict (${g("tenant")}, ${g("kind")}, ${g("code")}) do update set ${g("name")} = excluded.${g("name")}, ${g("updatedAt")} = now()
    returning x.${g("id")}, x.${g("updatedAt")} into v_id, v_updated;
  else
    begin
      update ${groups} x set ${g("kind")} = v_kind, ${g("code")} = v_code, ${g("name")} = v_name, ${g("updatedAt")} = now()
      where x.${g("id")} = import_discount_group.subject_id::uuid and x.${g("tenant")} = v_tenant
      returning x.${g("id")}, x.${g("updatedAt")} into v_id, v_updated;
    exception when unique_violation then
      ${fail("IMPORT_ITEM_INVALID", "another group of this kind has this code", "22023")}
    end;
    if v_id is null then
      ${fail("IMPORT_ITEM_INVALID", "the discount group no longer exists", "22023")}
    end if;
  end if;
  if v_data ? 'parties' then
    delete from ${members} x where x.${m("group")} = v_id and x.${m("party")} not in (select jsonb_array_elements_text(v_data -> 'parties'));
    insert into ${members} as x (${m("tenant")}, ${m("group")}, ${m("party")})
    select v_tenant, v_id, btrim(p) from jsonb_array_elements_text(v_data -> 'parties') p where length(btrim(p)) between 1 and 200
    on conflict (${m("tenant")}, ${m("party")}) do update set ${m("group")} = excluded.${m("group")};
  end if;
  return jsonb_build_object('subjectId', v_id::text, 'updatedAt', v_updated);
end;
$$;
${serviceGrant(`${fn("import_discount_group")}(uuid, jsonb, text)`)}

-- When a discount group last changed, for the conflict check of imports.
create or replace function ${fn("discount_group_updated_at")}(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select x.${g("updatedAt")} from ${groups} x where x.${g("id")} = $1::uuid
$$;
${serviceGrant(`${fn("discount_group_updated_at")}(text)`)}

-- The import target of the discount_rule entity: item.data is {
-- customerGroup?, productGroup? (group codes) or customerGroupId?,
-- productGroupId?, validFrom?, validTo?, minQuantity?, discountBps?,
-- fixedPrice?, currency? }. Import groups first.
create or replace function ${fn("import_discount_rule")}(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType} := (import_discount_rule.item ->> 'tenant')::${ctx.idType};
  v_data jsonb := import_discount_rule.item -> 'data';
  v_customer_id uuid;
  v_product_id uuid;
  v_customer_code text := nullif(btrim(v_data ->> 'customerGroup'), '');
  v_product_code text := nullif(btrim(v_data ->> 'productGroup'), '');
  v_customer uuid;
  v_product uuid;
  v_attrs jsonb;
  v_id uuid;
  v_updated timestamptz;
begin
  begin
    v_customer_id := nullif(v_data ->> 'customerGroupId', '')::uuid;
    v_product_id := nullif(v_data ->> 'productGroupId', '')::uuid;
  exception when invalid_text_representation then
    ${fail("IMPORT_ITEM_INVALID", "group ids are uuids", "22023")}
  end;
  v_customer := ${customerOf};
  v_product := ${productOf};
  if (v_customer_id is not null or v_customer_code is not null) and v_customer is null then
    ${fail("IMPORT_ITEM_INVALID", "the customer group isn't in this organization; import the groups first", "22023")}
  end if;
  if (v_product_id is not null or v_product_code is not null) and v_product is null then
    ${fail("IMPORT_ITEM_INVALID", "the product group isn't in this organization; import the groups first", "22023")}
  end if;
  v_attrs := jsonb_strip_nulls(jsonb_build_object('customerGroupId', v_customer, 'productGroupId', v_product, 'validFrom', v_data -> 'validFrom', 'validTo', v_data -> 'validTo',
    'minQuantity', v_data -> 'minQuantity', 'discountBps', v_data -> 'discountBps', 'fixedPrice', v_data -> 'fixedPrice', 'currency', v_data -> 'currency'));
  begin
    perform ${fn("discount_rule_check")}(v_tenant, v_attrs);
  exception when sqlstate '22023' or sqlstate 'P0002' then
    ${fail("IMPORT_ITEM_INVALID", "the rule isn't valid: check the groups, dates, discountBps, minQuantity and fixed price", "22023")}
  end;
  if import_discount_rule.subject_id is null then
    insert into ${rules} as x (${r("tenant")}, ${r("customerGroup")}, ${r("productGroup")}, ${r("validFrom")}, ${r("validTo")}, ${r("minQuantity")}, ${r("discountBps")}, ${r("fixedPrice")}, ${r("currency")})
    values (v_tenant, v_customer, v_product, (v_attrs ->> 'validFrom')::date, (v_attrs ->> 'validTo')::date, coalesce((v_attrs ->> 'minQuantity')::numeric, 0),
      coalesce((v_attrs ->> 'discountBps')::integer, 0), (v_attrs ->> 'fixedPrice')::bigint, v_attrs ->> 'currency')
    on conflict (${r("tenant")}, coalesce(${r("customerGroup")}, ${NO_GROUP}), coalesce(${r("productGroup")}, ${NO_GROUP}), coalesce(${r("validFrom")}, date '0001-01-01'), ${r("minQuantity")}) do update set
      ${r("validTo")} = excluded.${r("validTo")}, ${r("discountBps")} = excluded.${r("discountBps")}, ${r("fixedPrice")} = excluded.${r("fixedPrice")},
      ${r("currency")} = excluded.${r("currency")}, ${r("updatedAt")} = now()
    returning x.${r("id")}, x.${r("updatedAt")} into v_id, v_updated;
  else
    begin
      update ${rules} x set ${r("customerGroup")} = v_customer, ${r("productGroup")} = v_product, ${r("validFrom")} = (v_attrs ->> 'validFrom')::date, ${r("validTo")} = (v_attrs ->> 'validTo')::date,
        ${r("minQuantity")} = coalesce((v_attrs ->> 'minQuantity')::numeric, 0), ${r("discountBps")} = coalesce((v_attrs ->> 'discountBps')::integer, 0),
        ${r("fixedPrice")} = (v_attrs ->> 'fixedPrice')::bigint, ${r("currency")} = v_attrs ->> 'currency', ${r("updatedAt")} = now()
      where x.${r("id")} = import_discount_rule.subject_id::uuid and x.${r("tenant")} = v_tenant
      returning x.${r("id")}, x.${r("updatedAt")} into v_id, v_updated;
    exception when unique_violation then
      ${fail("IMPORT_ITEM_INVALID", "another rule has the same groups, start date and minimum quantity", "22023")}
    end;
    if v_id is null then
      ${fail("IMPORT_ITEM_INVALID", "the discount rule no longer exists", "22023")}
    end if;
  end if;
  return jsonb_build_object('subjectId', v_id::text, 'updatedAt', v_updated);
end;
$$;
${serviceGrant(`${fn("import_discount_rule")}(uuid, jsonb, text)`)}

create or replace function ${fn("discount_rule_updated_at")}(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select x.${r("updatedAt")} from ${rules} x where x.${r("id")} = $1::uuid
$$;
${serviceGrant(`${fn("discount_rule_updated_at")}(text)`)}
`;
}

/** The functions of the discount groups, the matrix and its imports. */
export function discountFunctions(ctx: BlockSqlContext, names: Names): string {
  if (!discountsOn(ctx)) {
    return "";
  }

  return `${groupFunctions(ctx, names)}${importFunctions(ctx, names)}`;
}

export function discountContract(
  ctx: BlockSqlContext,
): readonly BlockSqlContractFunction[] {
  if (!discountsOn(ctx)) {
    return [];
  }

  return [
    {
      name: "save_discount_group",
      args: ["{id}", "uuid", "text", "text", "text"],
      returns: "jsonb",
    },
    { name: "delete_discount_group", args: ["uuid"], returns: "boolean" },
    {
      name: "set_party_discount_group",
      args: ["{id}", "text", "uuid"],
      returns: "boolean",
    },
    {
      name: "save_discount_rule",
      args: ["{id}", "uuid", "jsonb"],
      returns: "jsonb",
    },
    { name: "delete_discount_rule", args: ["uuid"], returns: "boolean" },
    {
      name: "resolve_line_discount",
      args: ["{id}", "text", "uuid", "numeric", "date", "text"],
      returns: "jsonb",
    },
    ...(ctx.has("variants", "discountGroup")
      ? ([
          {
            name: "set_variant_discount_group",
            args: ["uuid", "uuid"],
            returns: "boolean",
          },
        ] as const)
      : []),
  ];
}

/** An import target names its functions as `schema.function`, without quotes. */
const plain = (qualified: string): string => qualified.replaceAll('"', "");

/** What `contributes.imports` adds for the discount groups and rules. */
function discountImportTargets(
  own: BlockSqlContext,
): readonly ImportTargetContribution[] {
  if (!discountsOn(own)) {
    return [];
  }

  return [
    {
      entity: "discount_group",
      subjectType: "discount_group",
      write: plain(own.fn("import_discount_group")),
      updatedAt: plain(own.fn("discount_group_updated_at")),
    },
    {
      entity: "discount_rule",
      subjectType: "discount_rule",
      write: plain(own.fn("import_discount_rule")),
      updatedAt: plain(own.fn("discount_rule_updated_at")),
    },
  ];
}

/** Every import target the catalog contributes: supply and discounts. */
export function catalogImportTargets(
  own: BlockSqlContext,
): readonly ImportTargetContribution[] {
  return [...supplyImportTargets(own), ...discountImportTargets(own)];
}
