import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";
import type { ImportTargetContribution } from "../contributions.ts";
import type { Names } from "./catalog-names.ts";

import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { fail, lockTable, serviceGrant, userGrant } from "../shared.ts";
import { guard } from "./catalog-functions.ts";

/** The identifier types `product_identifiers.type` accepts. */
const IDENTIFIER_TYPES = ["ean", "supplier", "manufacturer", "other"] as const;

/** The relation kinds `product_relations.kind` accepts. */
const RELATION_KINDS = ["alternative", "superseded_by", "accessory"] as const;

/** The fields a supplier column mapping can fill. */
const MAPPING_FIELDS = [
  "code",
  "description",
  "price",
  "currency",
  "unit",
  "keywords",
] as const;

const NO_PARTY = "'00000000-0000-0000-0000-000000000000'::uuid";

const list = (values: readonly string[]): string =>
  values.map((value) => `'${value}'`).join(", ");

/**
 * Whether a table added in version 5 exists: always when managed, and when the
 * app maps it on an adopted catalog.
 */
function supplyTable(ctx: BlockSqlContext, table: string): boolean {
  return ctx.hasTable(table) && (ctx.manages || !ctx.owns(table));
}

const identifiersOn = (ctx: BlockSqlContext): boolean =>
  supplyTable(ctx, "identifiers");

const relationsOn = (ctx: BlockSqlContext): boolean =>
  supplyTable(ctx, "relations");

const supplierItemsOn = (ctx: BlockSqlContext): boolean =>
  supplyTable(ctx, "supplierItems");

const mappingsOn = (ctx: BlockSqlContext): boolean =>
  supplierItemsOn(ctx) && supplyTable(ctx, "supplierItemMappings");

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

/**
 * The columns version 5 adds to existing tables, as `alter table` statements:
 * `create table if not exists` leaves an installed table alone.
 */
export function supplyColumns(ctx: BlockSqlContext): string {
  if (!ctx.manages || !ctx.has("variants", "tradeCode")) {
    return "";
  }

  const column = ctx.col("variants", "tradeCode");

  return `
-- The Combined Nomenclature code (4 to 10 digits) customs and Intrastat use.
alter table ${ctx.table("variants")} add column if not exists ${column} text;
alter table ${ctx.table("variants")} drop constraint if exists ${ctx.naming.rename("product_variants_trade_code_check")};
alter table ${ctx.table("variants")} add constraint ${ctx.naming.rename("product_variants_trade_code_check")} check (${column} ~ '^[0-9]{4,10}$');`;
}

/** The identifier, relation and supplier item tables (managed mode). */
export function supplyTables(ctx: BlockSqlContext, names: Names): string {
  if (!ctx.manages) {
    return "";
  }

  const t = (name: string): string => ctx.table(name);
  const c = (table: string, column: string): string => ctx.col(table, column);
  const parts: string[] = [];

  if (identifiersOn(ctx)) {
    parts.push(`
create table if not exists ${t("identifiers")} (
  ${c("identifiers", "id")} uuid primary key default gen_random_uuid(),
  ${c("identifiers", "tenant")} ${ctx.idType} not null,
  ${c("identifiers", "variant")} uuid not null references ${t("variants")} (${c("variants", "id")}) on delete cascade,
  ${c("identifiers", "type")} text not null check (${c("identifiers", "type")} in (${list(IDENTIFIER_TYPES)})),
  ${c("identifiers", "value")} text not null check (length(${c("identifiers", "value")}) between 1 and 100),
  -- The supplier or manufacturer the code belongs to; a soft reference, so the
  -- contacts block stays optional.
  ${c("identifiers", "party")} uuid,
  ${c("identifiers", "createdAt")} timestamptz not null default now(),
  ${c("identifiers", "updatedAt")} timestamptz not null default now()
);
create unique index if not exists ${ctx.naming.rename("product_identifiers_key")} on ${t("identifiers")} (${c("identifiers", "variant")}, ${c("identifiers", "type")}, ${c("identifiers", "value")}, coalesce(${c("identifiers", "party")}, ${NO_PARTY}));
create index if not exists ${ctx.naming.rename("product_identifiers_lookup_idx")} on ${t("identifiers")} (${c("identifiers", "tenant")}, ${c("identifiers", "type")}, ${c("identifiers", "value")});
${lockTable(t("identifiers"), { read: true })}
${readPolicy(ctx, names, "identifiers")}`);
  }

  if (relationsOn(ctx)) {
    parts.push(`
-- A relation points from a variant to another: the variant "from" has the
-- alternative, is superseded by the variant "to", or has it as an accessory.
create table if not exists ${t("relations")} (
  ${c("relations", "tenant")} ${ctx.idType} not null,
  ${c("relations", "from")} uuid not null references ${t("variants")} (${c("variants", "id")}) on delete cascade,
  ${c("relations", "to")} uuid not null references ${t("variants")} (${c("variants", "id")}) on delete cascade,
  ${c("relations", "kind")} text not null check (${c("relations", "kind")} in (${list(RELATION_KINDS)})),
  ${c("relations", "createdAt")} timestamptz not null default now(),
  primary key (${c("relations", "from")}, ${c("relations", "to")}, ${c("relations", "kind")}),
  check (${c("relations", "from")} <> ${c("relations", "to")})
);
create index if not exists ${ctx.naming.rename("product_relations_to_idx")} on ${t("relations")} (${c("relations", "to")}, ${c("relations", "kind")});
${lockTable(t("relations"), { read: true })}
${readPolicy(ctx, names, "relations")}`);
  }

  if (supplierItemsOn(ctx)) {
    parts.push(`
-- What a supplier sells under its own code. A row becomes a catalog variant
-- when it is first used (promote_supplier_item).
create table if not exists ${t("supplierItems")} (
  ${c("supplierItems", "id")} uuid primary key default gen_random_uuid(),
  ${c("supplierItems", "tenant")} ${ctx.idType} not null,
  ${c("supplierItems", "supplier")} uuid not null,
  ${c("supplierItems", "code")} text not null check (length(${c("supplierItems", "code")}) between 1 and 100),
  ${c("supplierItems", "description")} text,
  ${c("supplierItems", "price")} bigint check (${c("supplierItems", "price")} >= 0),
  ${c("supplierItems", "currency")} char(3) check (${c("supplierItems", "currency")} ~ '^[A-Z]{3}$'),
  ${c("supplierItems", "unit")} text,
  ${c("supplierItems", "keywordsText")} text,
  ${c("supplierItems", "keywords")} tsvector generated always as (to_tsvector('simple', ${c("supplierItems", "code")} || ' ' || coalesce(${c("supplierItems", "description")}, '') || ' ' || coalesce(${c("supplierItems", "keywordsText")}, ''))) stored,
  ${c("supplierItems", "variant")} uuid references ${t("variants")} (${c("variants", "id")}) on delete set null,
  ${c("supplierItems", "createdAt")} timestamptz not null default now(),
  ${c("supplierItems", "updatedAt")} timestamptz not null default now(),
  unique (${c("supplierItems", "tenant")}, ${c("supplierItems", "supplier")}, ${c("supplierItems", "code")})
);
create index if not exists ${ctx.naming.rename("supplier_items_keywords_idx")} on ${t("supplierItems")} using gin (${c("supplierItems", "keywords")});
create index if not exists ${ctx.naming.rename("supplier_items_variant_idx")} on ${t("supplierItems")} (${c("supplierItems", "variant")});
${lockTable(t("supplierItems"), { read: true })}
${readPolicy(ctx, names, "supplierItems")}`);
  }

  if (mappingsOn(ctx)) {
    parts.push(`
-- Which column of a supplier's price list fills which field: columns maps
-- code, description, price, currency, unit and keywords to source column names
-- (keywords may list several); defaults holds the currency and unit for rows
-- that carry none.
create table if not exists ${t("supplierItemMappings")} (
  ${c("supplierItemMappings", "tenant")} ${ctx.idType} not null,
  ${c("supplierItemMappings", "supplier")} uuid not null,
  ${c("supplierItemMappings", "columns")} jsonb not null check (jsonb_typeof(${c("supplierItemMappings", "columns")}) = 'object'),
  ${c("supplierItemMappings", "defaults")} jsonb not null default '{}'::jsonb check (jsonb_typeof(${c("supplierItemMappings", "defaults")}) = 'object'),
  ${c("supplierItemMappings", "updatedAt")} timestamptz not null default now(),
  primary key (${c("supplierItemMappings", "tenant")}, ${c("supplierItemMappings", "supplier")})
);
${lockTable(t("supplierItemMappings"), { read: true })}
${readPolicy(ctx, names, "supplierItemMappings")}`);
  }

  return parts.join("\n");
}

/** The type and value validation shared by the function and the import. */
const checks = (
  value: string,
  type: string,
): string => `if ${type} is null or ${type} not in (${list(IDENTIFIER_TYPES)}) then
    ${fail("CATALOG_IDENTIFIER_TYPE_INVALID", `the type must be one of ${IDENTIFIER_TYPES.join(", ")}`, "22023")}
  end if;
  if ${value} is null or length(${value}) not between 1 and 100 then
    ${fail("CATALOG_IDENTIFIER_INVALID", "the value must be 1 to 100 characters", "22023")}
  end if;
  if ${type} = 'ean' and ${value} !~ '^([0-9]{8}|[0-9]{12,14})$' then
    ${fail("CATALOG_IDENTIFIER_INVALID", "an EAN has 8, 12, 13 or 14 digits", "22023")}
  end if;`;

function identifierFunctions(ctx: BlockSqlContext, names: Names): string {
  const { fn } = names;
  const identifiers = ctx.table("identifiers");
  const variants = ctx.table("variants");
  const i = (column: string): string => ctx.col("identifiers", column);
  const v = (column: string): string => ctx.col("variants", column);

  return `
-- Adds an identifier (an EAN, a supplier's or manufacturer's code) to a
-- variant. A code is stored once per variant, type and party, so a second
-- call returns the existing row with created false.
create or replace function ${fn("save_product_identifier")}(tenant ${ctx.idType}, variant uuid, type text, value text, party uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_created boolean := false;
  v_value text := btrim(save_product_identifier.value);
begin
  ${guard(names, "save_product_identifier.tenant")}
  ${checks("v_value", "save_product_identifier.type")}
  if not exists (select 1 from ${variants} x where x.${v("id")} = save_product_identifier.variant and x.${v("tenant")} = save_product_identifier.tenant) then
    ${fail("CATALOG_VARIANT_NOT_FOUND", "variant not found", "P0002")}
  end if;
  select x.${i("id")} into v_id from ${identifiers} x
  where x.${i("variant")} = save_product_identifier.variant and x.${i("type")} = save_product_identifier.type and x.${i("value")} = v_value
    and coalesce(x.${i("party")}, ${NO_PARTY}) = coalesce(save_product_identifier.party, ${NO_PARTY});
  if v_id is null then
    begin
      insert into ${identifiers} as x (${i("tenant")}, ${i("variant")}, ${i("type")}, ${i("value")}, ${i("party")})
      values (save_product_identifier.tenant, save_product_identifier.variant, save_product_identifier.type, v_value, save_product_identifier.party)
      returning x.${i("id")} into v_id;
      v_created := true;
    exception when unique_violation then
      select x.${i("id")} into v_id from ${identifiers} x
      where x.${i("variant")} = save_product_identifier.variant and x.${i("type")} = save_product_identifier.type and x.${i("value")} = v_value
        and coalesce(x.${i("party")}, ${NO_PARTY}) = coalesce(save_product_identifier.party, ${NO_PARTY});
    end;
  end if;
  return jsonb_build_object('id', v_id, 'created', v_created);
end;
$$;
${userGrant(`${fn("save_product_identifier")}(${ctx.idType}, uuid, text, text, uuid)`)}

-- Removes an identifier.
create or replace function ${fn("delete_product_identifier")}(identifier uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  select x.${i("tenant")} into v_tenant from ${identifiers} x where x.${i("id")} = delete_product_identifier.identifier;
  if v_tenant is null then
    return false;
  end if;
  ${guard(names, "v_tenant")}
  delete from ${identifiers} x where x.${i("id")} = delete_product_identifier.identifier;
  return true;
end;
$$;
${userGrant(`${fn("delete_product_identifier")}(uuid)`)}

-- The variants that carry a code, with the identifier that matched. type and
-- party narrow the search; the caller's read access limits the rows.
create or replace function ${fn("find_variants_by_identifier")}(tenant ${ctx.idType}, value text, type text default null, party uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('identifierId', x.${i("id")}, 'variantId', y.${v("id")}, 'productId', y.${v("product")}, 'sku', y.${v("sku")}, 'type', x.${i("type")}, 'value', x.${i("value")}, 'partyId', x.${i("party")}) order by y.${v("sku")}, x.${i("type")}), '[]'::jsonb)
  from ${identifiers} x join ${variants} y on y.${v("id")} = x.${i("variant")}
  where x.${i("tenant")} = $1 and x.${i("value")} = btrim($2)
    and ($3 is null or x.${i("type")} = $3)
    and ($4 is null or x.${i("party")} = $4)
$$;
${userGrant(`${fn("find_variants_by_identifier")}(${ctx.idType}, text, text, uuid)`)}

-- Every identifier of a variant.
create or replace function ${fn("variant_identifiers")}(variant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x.${i("id")}, 'type', x.${i("type")}, 'value', x.${i("value")}, 'partyId', x.${i("party")}) order by x.${i("type")}, x.${i("value")}), '[]'::jsonb)
  from ${identifiers} x where x.${i("variant")} = $1
$$;
${userGrant(`${fn("variant_identifiers")}(uuid)`)}
`;
}

function relationFunctions(ctx: BlockSqlContext, names: Names): string {
  const { fn } = names;
  const relations = ctx.table("relations");
  const variants = ctx.table("variants");
  const r = (column: string): string => ctx.col("relations", column);
  const v = (column: string): string => ctx.col("variants", column);

  return `
-- Links the variant "from" to the variant "to": "from" has "to" as an
-- alternative or an accessory, or is superseded by it. A repeated call
-- returns created false. A supersession can't point back along its own chain.
create or replace function ${fn("save_product_relation")}(tenant ${ctx.idType}, from_variant uuid, to_variant uuid, kind text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_created boolean;
begin
  ${guard(names, "save_product_relation.tenant")}
  if save_product_relation.kind is null or save_product_relation.kind not in (${list(RELATION_KINDS)}) then
    ${fail("CATALOG_RELATION_KIND_INVALID", `the kind must be one of ${RELATION_KINDS.join(", ")}`, "22023")}
  end if;
  if save_product_relation.from_variant = save_product_relation.to_variant then
    ${fail("CATALOG_RELATION_INVALID", "a variant can't relate to itself", "22023")}
  end if;
  if (select count(*) from ${variants} x where x.${v("tenant")} = save_product_relation.tenant and x.${v("id")} in (save_product_relation.from_variant, save_product_relation.to_variant)) <> 2 then
    ${fail("CATALOG_VARIANT_NOT_FOUND", "variant not found", "P0002")}
  end if;
  if save_product_relation.kind = 'superseded_by' and exists (
    with recursive chain(id, depth) as (
      select save_product_relation.to_variant, 0
      union all
      select y.${r("to")}, c.depth + 1 from ${relations} y join chain c on y.${r("from")} = c.id and y.${r("kind")} = 'superseded_by' where c.depth < 50
    )
    select 1 from chain where id = save_product_relation.from_variant
  ) then
    ${fail("CATALOG_RELATION_CYCLE", "the replacement already points back at this variant", "22023")}
  end if;
  insert into ${relations} (${r("tenant")}, ${r("from")}, ${r("to")}, ${r("kind")})
  values (save_product_relation.tenant, save_product_relation.from_variant, save_product_relation.to_variant, save_product_relation.kind)
  on conflict do nothing;
  v_created := found;
  return jsonb_build_object('created', v_created);
end;
$$;
${userGrant(`${fn("save_product_relation")}(${ctx.idType}, uuid, uuid, text)`)}

-- Removes one relation.
create or replace function ${fn("delete_product_relation")}(from_variant uuid, to_variant uuid, kind text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  select x.${r("tenant")} into v_tenant from ${relations} x
  where x.${r("from")} = delete_product_relation.from_variant and x.${r("to")} = delete_product_relation.to_variant and x.${r("kind")} = delete_product_relation.kind;
  if v_tenant is null then
    return false;
  end if;
  ${guard(names, "v_tenant")}
  delete from ${relations} x
  where x.${r("from")} = delete_product_relation.from_variant and x.${r("to")} = delete_product_relation.to_variant and x.${r("kind")} = delete_product_relation.kind;
  return true;
end;
$$;
${userGrant(`${fn("delete_product_relation")}(uuid, uuid, text)`)}

-- The relations a variant is part of. direction is outgoing where the variant
-- is "from" (it is superseded by, or has as an alternative or accessory, the
-- variant named) and incoming where it is "to".
create or replace function ${fn("variant_relations")}(variant uuid, kind text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('kind', q.kind, 'direction', q.direction, 'variantId', q.other, 'sku', y.${v("sku")}) order by q.kind, q.direction, y.${v("sku")}), '[]'::jsonb)
  from (
    select x.${r("kind")} as kind, 'outgoing' as direction, x.${r("to")} as other from ${relations} x where x.${r("from")} = $1
    union all
    select x.${r("kind")}, 'incoming', x.${r("from")} from ${relations} x where x.${r("to")} = $1
  ) q
  join ${variants} y on y.${v("id")} = q.other
  where $2 is null or q.kind = $2
$$;
${userGrant(`${fn("variant_relations")}(uuid, text)`)}

-- The variant at the end of a variant's superseded_by chain: the variant
-- itself when nothing replaces it.
create or replace function ${fn("replacement_variant")}(variant uuid)
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  with recursive chain(id, depth) as (
    select $1, 0
    union all
    select x.${r("to")}, c.depth + 1 from ${relations} x join chain c on x.${r("from")} = c.id and x.${r("kind")} = 'superseded_by' where c.depth < 50
  )
  select id from chain order by depth desc, id limit 1
$$;
${userGrant(`${fn("replacement_variant")}(uuid)`)}
`;
}

function mappingFunctions(ctx: BlockSqlContext, names: Names): string {
  const { fn } = names;
  const mappings = ctx.table("supplierItemMappings");
  const m = (column: string): string => ctx.col("supplierItemMappings", column);

  return `
-- Sets how a supplier's price list columns fill supplier items. columns maps
-- ${MAPPING_FIELDS.join(", ")} to source column names (keywords
-- may list several); defaults may hold currency and unit.
create or replace function ${fn("set_supplier_item_mapping")}(tenant ${ctx.idType}, supplier uuid, columns jsonb, defaults jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_key text;
  v_value jsonb;
  v_defaults jsonb := coalesce(set_supplier_item_mapping.defaults, '{}'::jsonb);
begin
  ${guard(names, "set_supplier_item_mapping.tenant")}
  if jsonb_typeof(set_supplier_item_mapping.columns) is distinct from 'object' or jsonb_typeof(v_defaults) <> 'object' then
    ${fail("CATALOG_SUPPLIER_MAPPING_INVALID", "columns and defaults must be objects", "22023")}
  end if;
  for v_key, v_value in select e.key, e.value from jsonb_each(set_supplier_item_mapping.columns) e loop
    if v_key <> all (array[${list(MAPPING_FIELDS)}]) then
      ${fail("CATALOG_SUPPLIER_MAPPING_INVALID", `a mapping fills only ${MAPPING_FIELDS.join(", ")}`, "22023")}
    end if;
    if not (jsonb_typeof(v_value) = 'string' or (v_key = 'keywords' and jsonb_typeof(v_value) = 'array' and not exists (select 1 from jsonb_array_elements(v_value) a where jsonb_typeof(a.value) <> 'string'))) then
      ${fail("CATALOG_SUPPLIER_MAPPING_INVALID", "a mapping value is a source column name (keywords may list several)", "22023")}
    end if;
  end loop;
  if not (set_supplier_item_mapping.columns ? 'code') then
    ${fail("CATALOG_SUPPLIER_MAPPING_INVALID", "a mapping needs a code column", "22023")}
  end if;
  if exists (select 1 from jsonb_object_keys(v_defaults) k where k <> all (array['currency', 'unit'])) then
    ${fail("CATALOG_SUPPLIER_MAPPING_INVALID", "defaults may hold currency and unit", "22023")}
  end if;
  if v_defaults ? 'currency' and ${fn("currency_minor_units")}(v_defaults ->> 'currency') is null then
    ${fail("CATALOG_CURRENCY_INVALID", "not an ISO 4217 currency code", "22023")}
  end if;
  insert into ${mappings} as x (${m("tenant")}, ${m("supplier")}, ${m("columns")}, ${m("defaults")})
  values (set_supplier_item_mapping.tenant, set_supplier_item_mapping.supplier, set_supplier_item_mapping.columns, v_defaults)
  on conflict (${m("tenant")}, ${m("supplier")}) do update set ${m("columns")} = excluded.${m("columns")}, ${m("defaults")} = excluded.${m("defaults")}, ${m("updatedAt")} = now();
  return jsonb_build_object('supplierId', set_supplier_item_mapping.supplier, 'columns', set_supplier_item_mapping.columns, 'defaults', v_defaults);
end;
$$;
${userGrant(`${fn("set_supplier_item_mapping")}(${ctx.idType}, uuid, jsonb, jsonb)`)}

-- A supplier's mapping, or null.
create or replace function ${fn("supplier_item_mapping")}(tenant ${ctx.idType}, supplier uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('supplierId', x.${m("supplier")}, 'columns', x.${m("columns")}, 'defaults', x.${m("defaults")})
  from ${mappings} x where x.${m("tenant")} = $1 and x.${m("supplier")} = $2
$$;
${userGrant(`${fn("supplier_item_mapping")}(${ctx.idType}, uuid)`)}

-- Removes a supplier's mapping.
create or replace function ${fn("delete_supplier_item_mapping")}(tenant ${ctx.idType}, supplier uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  ${guard(names, "delete_supplier_item_mapping.tenant")}
  delete from ${mappings} x where x.${m("tenant")} = delete_supplier_item_mapping.tenant and x.${m("supplier")} = delete_supplier_item_mapping.supplier;
  return found;
end;
$$;
${userGrant(`${fn("delete_supplier_item_mapping")}(${ctx.idType}, uuid)`)}

-- One source row of a supplier's price list as supplier item fields, through
-- the supplier's mapping. price is in minor units: the source value is a
-- decimal in major units, with a comma or a dot as the decimal separator.
create or replace function ${fn("supplier_item_from_row")}(tenant ${ctx.idType}, supplier uuid, source jsonb)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_columns jsonb;
  v_defaults jsonb;
  v_code text;
  v_description text;
  v_unit text;
  v_currency text;
  v_price text;
  v_amount bigint;
  v_scale integer;
  v_keywords text;
  v_source jsonb;
begin
  select x.${m("columns")}, x.${m("defaults")} into v_columns, v_defaults
  from ${mappings} x where x.${m("tenant")} = supplier_item_from_row.tenant and x.${m("supplier")} = supplier_item_from_row.supplier;
  if v_columns is null then
    ${fail("CATALOG_SUPPLIER_MAPPING_NOT_FOUND", "this supplier has no column mapping", "P0002")}
  end if;
  if jsonb_typeof(supplier_item_from_row.source) is distinct from 'object' then
    ${fail("CATALOG_SUPPLIER_ROW_INVALID", "a row is an object of source columns", "22023")}
  end if;
  v_code := nullif(btrim(supplier_item_from_row.source ->> (v_columns ->> 'code')), '');
  v_description := nullif(btrim(supplier_item_from_row.source ->> (v_columns ->> 'description')), '');
  v_unit := coalesce(nullif(btrim(supplier_item_from_row.source ->> (v_columns ->> 'unit')), ''), v_defaults ->> 'unit');
  v_currency := upper(coalesce(nullif(btrim(supplier_item_from_row.source ->> (v_columns ->> 'currency')), ''), v_defaults ->> 'currency'));
  v_price := nullif(btrim(supplier_item_from_row.source ->> (v_columns ->> 'price')), '');
  if v_currency is not null and ${fn("currency_minor_units")}(v_currency) is null then
    ${fail("CATALOG_CURRENCY_INVALID", "not an ISO 4217 currency code", "22023")}
  end if;
  if v_price is not null then
    v_price := regexp_replace(v_price, '[^0-9.,-]', '', 'g');
    if position(',' in v_price) > 0 and position('.' in v_price) > 0 then
      -- The separator that comes last is the decimal one.
      if length(v_price) - length(regexp_replace(v_price, '^.*,', '')) > length(v_price) - length(regexp_replace(v_price, '^.*\\.', '')) then
        v_price := replace(replace(v_price, '.', ''), ',', '.');
      else
        v_price := replace(v_price, ',', '');
      end if;
    else
      v_price := replace(v_price, ',', '.');
    end if;
    v_scale := coalesce(${fn("currency_minor_units")}(v_currency), 2);
    begin
      v_amount := round(v_price::numeric * power(10::numeric, v_scale))::bigint;
    exception when others then
      ${fail("CATALOG_SUPPLIER_PRICE_INVALID", "the price is not a number", "22023")}
    end;
    if v_amount < 0 then
      ${fail("CATALOG_SUPPLIER_PRICE_INVALID", "the price can't be negative", "22023")}
    end if;
  end if;
  v_source := case jsonb_typeof(v_columns -> 'keywords') when 'array' then v_columns -> 'keywords' when 'string' then jsonb_build_array(v_columns -> 'keywords') else '[]'::jsonb end;
  select nullif(string_agg(btrim(supplier_item_from_row.source ->> (a.value #>> '{}')), ' ') filter (where nullif(btrim(supplier_item_from_row.source ->> (a.value #>> '{}')), '') is not null), '')
  into v_keywords from jsonb_array_elements(v_source) a;
  return jsonb_strip_nulls(jsonb_build_object('code', v_code, 'description', v_description, 'price', v_amount, 'currency', v_currency, 'unit', v_unit, 'keywords', v_keywords));
end;
$$;
${userGrant(`${fn("supplier_item_from_row")}(${ctx.idType}, uuid, jsonb)`)}
`;
}

function supplierItemFunctions(ctx: BlockSqlContext, names: Names): string {
  const { fn } = names;
  const items = ctx.table("supplierItems");
  const products = ctx.table("products");
  const variants = ctx.table("variants");
  const s = (column: string): string => ctx.col("supplierItems", column);
  const p = (column: string): string => ctx.col("products", column);
  const v = (column: string): string => ctx.col("variants", column);
  const identifiers = identifiersOn(ctx) ? ctx.table("identifiers") : "";
  const i = (column: string): string => ctx.col("identifiers", column);
  const description = ctx.has("products", "description");

  const identifier = identifiersOn(ctx)
    ? `
  insert into ${identifiers} (${i("tenant")}, ${i("variant")}, ${i("type")}, ${i("value")}, ${i("party")})
  values (v_item.${s("tenant")}, v_variant, 'supplier', v_item.${s("code")}, v_item.${s("supplier")})
  on conflict do nothing;`
    : "";

  return `${mappingsOn(ctx) ? mappingFunctions(ctx, names) : ""}
-- Creates a supplier item (item null) or updates one; on an update a null
-- argument keeps the column. price is in minor units.
create or replace function ${fn("save_supplier_item")}(tenant ${ctx.idType}, item uuid, supplier uuid, code text, description text, price bigint, currency text, unit text, keywords text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_supplier_item.item;
  v_code text := btrim(save_supplier_item.code);
begin
  ${guard(names, "save_supplier_item.tenant")}
  if v_code is null or length(v_code) not between 1 and 100 then
    ${fail("CATALOG_SUPPLIER_ITEM_INVALID", "the code must be 1 to 100 characters", "22023")}
  end if;
  if save_supplier_item.price is not null and save_supplier_item.price < 0 then
    ${fail("CATALOG_SUPPLIER_ITEM_INVALID", "the price can't be negative", "22023")}
  end if;
  if save_supplier_item.currency is not null and ${fn("currency_minor_units")}(save_supplier_item.currency) is null then
    ${fail("CATALOG_CURRENCY_INVALID", "not an ISO 4217 currency code", "22023")}
  end if;
  begin
    if v_id is null then
      insert into ${items} as x (${s("tenant")}, ${s("supplier")}, ${s("code")}, ${s("description")}, ${s("price")}, ${s("currency")}, ${s("unit")}, ${s("keywordsText")})
      values (save_supplier_item.tenant, save_supplier_item.supplier, v_code, save_supplier_item.description, save_supplier_item.price, save_supplier_item.currency, save_supplier_item.unit, save_supplier_item.keywords)
      returning x.${s("id")} into v_id;
    else
      update ${items} x set ${s("supplier")} = coalesce(save_supplier_item.supplier, x.${s("supplier")}), ${s("code")} = v_code,
        ${s("description")} = coalesce(save_supplier_item.description, x.${s("description")}), ${s("price")} = coalesce(save_supplier_item.price, x.${s("price")}),
        ${s("currency")} = coalesce(save_supplier_item.currency, x.${s("currency")}), ${s("unit")} = coalesce(save_supplier_item.unit, x.${s("unit")}),
        ${s("keywordsText")} = coalesce(save_supplier_item.keywords, x.${s("keywordsText")}), ${s("updatedAt")} = now()
      where x.${s("id")} = save_supplier_item.item and x.${s("tenant")} = save_supplier_item.tenant;
      if not found then
        ${fail("CATALOG_SUPPLIER_ITEM_NOT_FOUND", "supplier item not found", "P0002")}
      end if;
    end if;
  exception when unique_violation then
    ${fail("CATALOG_SUPPLIER_ITEM_TAKEN", "this supplier already has an item with this code", "23505")}
  end;
  return jsonb_build_object('id', v_id, 'code', v_code);
end;
$$;
${userGrant(`${fn("save_supplier_item")}(${ctx.idType}, uuid, uuid, text, text, bigint, text, text, text)`)}

-- Deletes a supplier item. The variant it was promoted to stays.
create or replace function ${fn("delete_supplier_item")}(item uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  select x.${s("tenant")} into v_tenant from ${items} x where x.${s("id")} = delete_supplier_item.item;
  if v_tenant is null then
    return false;
  end if;
  ${guard(names, "v_tenant")}
  delete from ${items} x where x.${s("id")} = delete_supplier_item.item;
  return true;
end;
$$;
${userGrant(`${fn("delete_supplier_item")}(uuid)`)}

-- Searches supplier items by words in the code, the description and the
-- keywords, and by the start of a code. The caller's read access limits the
-- rows; the best matches come first.
create or replace function ${fn("search_supplier_items")}(tenant ${ctx.idType}, query text, supplier uuid default null, row_limit integer default 25)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(r.item order by r.rank desc, r.code), '[]'::jsonb)
  from (
    select x.${s("code")} as code,
      ts_rank(x.${s("keywords")}, websearch_to_tsquery('simple', $2)) + case when x.${s("code")} ilike replace(replace($2, '%', ''), '_', '') || '%' then 1 else 0 end as rank,
      jsonb_build_object('id', x.${s("id")}, 'supplierId', x.${s("supplier")}, 'code', x.${s("code")}, 'description', x.${s("description")}, 'price', x.${s("price")}, 'currency', x.${s("currency")}, 'unit', x.${s("unit")}, 'variantId', x.${s("variant")}) as item
    from ${items} x
    where x.${s("tenant")} = $1 and ($3 is null or x.${s("supplier")} = $3)
      and (x.${s("keywords")} @@ websearch_to_tsquery('simple', $2) or x.${s("code")} ilike replace(replace($2, '%', ''), '_', '') || '%')
    order by 2 desc, 1
    limit least(greatest(coalesce($4, 25), 1), 200)
  ) r
$$;
${userGrant(`${fn("search_supplier_items")}(${ctx.idType}, text, uuid, integer)`)}

-- Makes a supplier item a catalog product on first use: a product and a variant
-- (sku defaults to the supplier's code), the supplier's code as an identifier,
-- and the link back on the item. A second call returns the same variant with
-- created false.
create or replace function ${fn("promote_supplier_item")}(item uuid, sku text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item ${items};
  v_sku text;
  v_slug text;
  v_product uuid;
  v_variant uuid;
begin
  select * into v_item from ${items} x where x.${s("id")} = promote_supplier_item.item for update;
  if not found then
    ${fail("CATALOG_SUPPLIER_ITEM_NOT_FOUND", "supplier item not found", "P0002")}
  end if;
  ${guard(names, `v_item.${s("tenant")}`, names.create)}
  if v_item.${s("variant")} is not null then
    select y.${v("product")} into v_product from ${variants} y where y.${v("id")} = v_item.${s("variant")};
    return jsonb_build_object('productId', v_product, 'variantId', v_item.${s("variant")}, 'created', false);
  end if;
  v_sku := btrim(coalesce(nullif(promote_supplier_item.sku, ''), v_item.${s("code")}));
  if length(v_sku) not between 1 and 100 then
    ${fail("CATALOG_SKU_INVALID", "the SKU must be 1 to 100 characters", "22023")}
  end if;
  v_slug := trim(both '-' from regexp_replace(lower(v_sku), '[^a-z0-9]+', '-', 'g'));
  if v_slug = '' then
    v_slug := 'item';
  end if;
  if exists (select 1 from ${products} x where x.${p("tenant")} = v_item.${s("tenant")} and x.${p("slug")} = v_slug) then
    v_slug := v_slug || '-' || substr(v_item.${s("id")}::text, 1, 8);
  end if;
  begin
    insert into ${products} as x (${p("tenant")}, ${p("title")}, ${p("slug")}${description ? `, ${p("description")}` : ""})
    values (v_item.${s("tenant")}, left(coalesce(nullif(v_item.${s("description")}, ''), v_item.${s("code")}), 500), v_slug${description ? `, v_item.${s("description")}` : ""})
    returning x.${p("id")} into v_product;
    insert into ${variants} as y (${v("tenant")}, ${v("product")}, ${v("sku")})
    values (v_item.${s("tenant")}, v_product, v_sku)
    returning y.${v("id")} into v_variant;
  exception when unique_violation then
    ${fail("CATALOG_SKU_TAKEN", "another variant has this SKU", "23505")}
  end;
  update ${items} x set ${s("variant")} = v_variant, ${s("updatedAt")} = now() where x.${s("id")} = v_item.${s("id")};${identifier}
  ${ctx.record({
    type: "product.created",
    payload: `jsonb_build_object('organizationId', v_item.${s("tenant")}, 'id', v_product, 'slug', v_slug, 'kind', null)`,
    subject: "'products/' || v_product::text",
    tenant: `v_item.${s("tenant")}`,
    audit: false,
  })}
  ${ctx.record({
    type: "product_variant.created",
    payload: `jsonb_build_object('organizationId', v_item.${s("tenant")}, 'id', v_variant, 'productId', v_product, 'sku', v_sku)`,
    subject: "'variants/' || v_variant::text",
    tenant: `v_item.${s("tenant")}`,
    audit: false,
  })}
  return jsonb_build_object('productId', v_product, 'variantId', v_variant, 'created', true);
end;
$$;
${userGrant(`${fn("promote_supplier_item")}(uuid, text)`)}
`;
}

function tradeCodeFunction(ctx: BlockSqlContext, names: Names): string {
  const { fn } = names;
  const variants = ctx.table("variants");
  const v = (column: string): string => ctx.col("variants", column);

  return `
-- Sets a variant's Combined Nomenclature code (4 to 10 digits; spaces are
-- dropped), or clears it with null.
create or replace function ${fn("set_variant_trade_code")}(variant uuid, trade_code text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_code text := nullif(replace(btrim(set_variant_trade_code.trade_code), ' ', ''), '');
begin
  select x.${v("tenant")} into v_tenant from ${variants} x where x.${v("id")} = set_variant_trade_code.variant;
  if v_tenant is null then
    ${fail("CATALOG_VARIANT_NOT_FOUND", "variant not found", "P0002")}
  end if;
  ${guard(names, "v_tenant", names.update)}
  if v_code is not null and v_code !~ '^[0-9]{4,10}$' then
    ${fail("CATALOG_TRADE_CODE_INVALID", "a trade code has 4 to 10 digits", "22023")}
  end if;
  update ${variants} x set ${v("tradeCode")} = v_code, ${v("updatedAt")} = now() where x.${v("id")} = set_variant_trade_code.variant;
  return true;
end;
$$;
${userGrant(`${fn("set_variant_trade_code")}(uuid, text)`)}
`;
}

function importFunctions(ctx: BlockSqlContext, names: Names): string {
  const { fn } = names;
  const items = ctx.table("supplierItems");
  const s = (column: string): string => ctx.col("supplierItems", column);
  const variants = ctx.table("variants");
  const v = (column: string): string => ctx.col("variants", column);
  const identifiers = ctx.table("identifiers");
  const i = (column: string): string => ctx.col("identifiers", column);

  const supplierWrite = supplierItemsOn(ctx)
    ? `
-- The import target of the supplier_item entity (ADR 0141): item.data is {
-- supplierId, row?, code?, description?, price?, currency?, unit?, keywords? }.
-- A row goes through the supplier's column mapping; the fields named next to
-- it win. price is in minor units. A key that is new but names a code the
-- supplier already has takes over that row.
create or replace function ${fn("import_supplier_item")}(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType} := (import_supplier_item.item ->> 'tenant')::${ctx.idType};
  v_data jsonb := import_supplier_item.item -> 'data';
  v_supplier uuid;
  v_merged jsonb;
  v_code text;
  v_price text;
  v_id uuid;
  v_updated timestamptz;
begin
  begin
    v_supplier := nullif(v_data ->> 'supplierId', '')::uuid;
  exception when invalid_text_representation then
    ${fail("IMPORT_ITEM_INVALID", "supplierId must be a uuid", "22023")}
  end;
  if v_supplier is null then
    ${fail("IMPORT_ITEM_INVALID", "a supplier item needs a supplierId", "22023")}
  end if;
  v_merged := (case when jsonb_typeof(v_data -> 'row') = 'object' then ${mappingsOn(ctx) ? `${fn("supplier_item_from_row")}(v_tenant, v_supplier, v_data -> 'row')` : "'{}'::jsonb"} else '{}'::jsonb end) || (v_data - 'row' - 'supplierId');
  v_code := nullif(btrim(v_merged ->> 'code'), '');
  v_price := v_merged ->> 'price';
  if v_code is null or length(v_code) > 100 then
    ${fail("IMPORT_ITEM_INVALID", "a supplier item needs a code of up to 100 characters", "22023")}
  end if;
  if v_price is not null and v_price !~ '^[0-9]{1,18}$' then
    ${fail("IMPORT_ITEM_INVALID", "price is a whole number of minor units", "22023")}
  end if;
  if v_merged ->> 'currency' is not null and ${fn("currency_minor_units")}(upper(v_merged ->> 'currency')) is null then
    ${fail("IMPORT_ITEM_INVALID", "not an ISO 4217 currency code", "22023")}
  end if;
  if import_supplier_item.subject_id is null then
    insert into ${items} as x (${s("tenant")}, ${s("supplier")}, ${s("code")}, ${s("description")}, ${s("price")}, ${s("currency")}, ${s("unit")}, ${s("keywordsText")})
    values (v_tenant, v_supplier, v_code, v_merged ->> 'description', v_price::bigint, upper(v_merged ->> 'currency'), v_merged ->> 'unit', v_merged ->> 'keywords')
    on conflict (${s("tenant")}, ${s("supplier")}, ${s("code")}) do update set ${s("description")} = excluded.${s("description")}, ${s("price")} = excluded.${s("price")},
      ${s("currency")} = excluded.${s("currency")}, ${s("unit")} = excluded.${s("unit")}, ${s("keywordsText")} = excluded.${s("keywordsText")}, ${s("updatedAt")} = now()
    returning x.${s("id")}, x.${s("updatedAt")} into v_id, v_updated;
  else
    update ${items} x set ${s("supplier")} = v_supplier, ${s("code")} = v_code, ${s("description")} = v_merged ->> 'description', ${s("price")} = v_price::bigint,
      ${s("currency")} = upper(v_merged ->> 'currency'), ${s("unit")} = v_merged ->> 'unit', ${s("keywordsText")} = v_merged ->> 'keywords', ${s("updatedAt")} = now()
    where x.${s("id")} = import_supplier_item.subject_id::uuid and x.${s("tenant")} = v_tenant
    returning x.${s("id")}, x.${s("updatedAt")} into v_id, v_updated;
    if not found then
      ${fail("IMPORT_ITEM_INVALID", "the supplier item no longer exists", "22023")}
    end if;
  end if;
  return jsonb_build_object('subjectId', v_id::text, 'updatedAt', v_updated);
end;
$$;
${serviceGrant(`${fn("import_supplier_item")}(uuid, jsonb, text)`)}

-- When a supplier item last changed, for the conflict check of imports.
create or replace function ${fn("supplier_item_updated_at")}(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select x.${s("updatedAt")} from ${items} x where x.${s("id")} = $1::uuid
$$;
${serviceGrant(`${fn("supplier_item_updated_at")}(text)`)}
`
    : "";

  const identifierWrite = identifiersOn(ctx)
    ? `
-- The import target of the product_identifier entity: item.data is { sku or
-- variantId, type, value, partyId? }. A key that is new but names a code the
-- variant already has takes over that row.
create or replace function ${fn("import_product_identifier")}(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType} := (import_product_identifier.item ->> 'tenant')::${ctx.idType};
  v_data jsonb := import_product_identifier.item -> 'data';
  v_variant uuid;
  v_type text := v_data ->> 'type';
  v_value text := btrim(v_data ->> 'value');
  v_party uuid;
  v_id uuid;
  v_updated timestamptz;
begin
  begin
    v_variant := nullif(v_data ->> 'variantId', '')::uuid;
    v_party := nullif(v_data ->> 'partyId', '')::uuid;
  exception when invalid_text_representation then
    ${fail("IMPORT_ITEM_INVALID", "variantId and partyId must be uuids", "22023")}
  end;
  if v_variant is null and nullif(v_data ->> 'sku', '') is not null then
    select y.${v("id")} into v_variant from ${variants} y where y.${v("tenant")} = v_tenant and y.${v("sku")} = v_data ->> 'sku';
  end if;
  if v_variant is null or not exists (select 1 from ${variants} y where y.${v("id")} = v_variant and y.${v("tenant")} = v_tenant) then
    ${fail("IMPORT_ITEM_INVALID", "the variant isn't in this organization; name it with sku or variantId", "22023")}
  end if;
  ${checks("v_value", "v_type")}
  if import_product_identifier.subject_id is null then
    insert into ${identifiers} as x (${i("tenant")}, ${i("variant")}, ${i("type")}, ${i("value")}, ${i("party")})
    values (v_tenant, v_variant, v_type, v_value, v_party)
    on conflict (${i("variant")}, ${i("type")}, ${i("value")}, coalesce(${i("party")}, ${NO_PARTY})) do update set ${i("updatedAt")} = now()
    returning x.${i("id")}, x.${i("updatedAt")} into v_id, v_updated;
  else
    update ${identifiers} x set ${i("variant")} = v_variant, ${i("type")} = v_type, ${i("value")} = v_value, ${i("party")} = v_party, ${i("updatedAt")} = now()
    where x.${i("id")} = import_product_identifier.subject_id::uuid and x.${i("tenant")} = v_tenant
    returning x.${i("id")}, x.${i("updatedAt")} into v_id, v_updated;
    if not found then
      ${fail("IMPORT_ITEM_INVALID", "the identifier no longer exists", "22023")}
    end if;
  end if;
  return jsonb_build_object('subjectId', v_id::text, 'updatedAt', v_updated);
end;
$$;
${serviceGrant(`${fn("import_product_identifier")}(uuid, jsonb, text)`)}

create or replace function ${fn("product_identifier_updated_at")}(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select x.${i("updatedAt")} from ${identifiers} x where x.${i("id")} = $1::uuid
$$;
${serviceGrant(`${fn("product_identifier_updated_at")}(text)`)}
`
    : "";

  return `${supplierWrite}${identifierWrite}`;
}

/** The functions of identifiers, relations, supplier items and trade codes. */
export function supplyFunctions(ctx: BlockSqlContext, names: Names): string {
  return `${identifiersOn(ctx) ? identifierFunctions(ctx, names) : ""}${relationsOn(ctx) ? relationFunctions(ctx, names) : ""}${supplierItemsOn(ctx) ? supplierItemFunctions(ctx, names) : ""}${ctx.has("variants", "tradeCode") ? tradeCodeFunction(ctx, names) : ""}${importFunctions(ctx, names)}`;
}

export function supplyContract(
  ctx: BlockSqlContext,
): readonly BlockSqlContractFunction[] {
  return [
    ...(identifiersOn(ctx)
      ? ([
          {
            name: "save_product_identifier",
            args: ["{id}", "uuid", "text", "text", "uuid"],
            returns: "jsonb",
          },
          {
            name: "delete_product_identifier",
            args: ["uuid"],
            returns: "boolean",
          },
          {
            name: "find_variants_by_identifier",
            args: ["{id}", "text", "text", "uuid"],
            returns: "jsonb",
          },
          { name: "variant_identifiers", args: ["uuid"], returns: "jsonb" },
        ] as const)
      : []),
    ...(relationsOn(ctx)
      ? ([
          {
            name: "save_product_relation",
            args: ["{id}", "uuid", "uuid", "text"],
            returns: "jsonb",
          },
          {
            name: "delete_product_relation",
            args: ["uuid", "uuid", "text"],
            returns: "boolean",
          },
          {
            name: "variant_relations",
            args: ["uuid", "text"],
            returns: "jsonb",
          },
          { name: "replacement_variant", args: ["uuid"], returns: "uuid" },
        ] as const)
      : []),
    ...(supplierItemsOn(ctx)
      ? ([
          {
            name: "save_supplier_item",
            args: [
              "{id}",
              "uuid",
              "uuid",
              "text",
              "text",
              "bigint",
              "text",
              "text",
              "text",
            ],
            returns: "jsonb",
          },
          { name: "delete_supplier_item", args: ["uuid"], returns: "boolean" },
          {
            name: "search_supplier_items",
            args: ["{id}", "text", "uuid", "integer"],
            returns: "jsonb",
          },
          {
            name: "promote_supplier_item",
            args: ["uuid", "text"],
            returns: "jsonb",
          },
        ] as const)
      : []),
    ...(mappingsOn(ctx)
      ? ([
          {
            name: "set_supplier_item_mapping",
            args: ["{id}", "uuid", "jsonb", "jsonb"],
            returns: "jsonb",
          },
          {
            name: "supplier_item_mapping",
            args: ["{id}", "uuid"],
            returns: "jsonb",
          },
          {
            name: "delete_supplier_item_mapping",
            args: ["{id}", "uuid"],
            returns: "boolean",
          },
          {
            name: "supplier_item_from_row",
            args: ["{id}", "uuid", "jsonb"],
            returns: "jsonb",
          },
        ] as const)
      : []),
    ...(ctx.has("variants", "tradeCode")
      ? ([
          {
            name: "set_variant_trade_code",
            args: ["uuid", "text"],
            returns: "boolean",
          },
        ] as const)
      : []),
  ];
}

/** An import target names its functions as `schema.function`, without quotes. */
const plain = (qualified: string): string => qualified.replaceAll('"', "");

/** What `contributes.imports` returns: the supplier item and identifier targets. */
export function supplyImportTargets(
  own: BlockSqlContext,
): readonly ImportTargetContribution[] {
  return [
    ...(supplierItemsOn(own)
      ? [
          {
            entity: "supplier_item",
            subjectType: "supplier_item",
            write: plain(own.fn("import_supplier_item")),
            updatedAt: plain(own.fn("supplier_item_updated_at")),
          },
        ]
      : []),
    ...(identifiersOn(own)
      ? [
          {
            entity: "product_identifier",
            subjectType: "product_identifier",
            write: plain(own.fn("import_product_identifier")),
            updatedAt: plain(own.fn("product_identifier_updated_at")),
          },
        ]
      : []),
  ];
}
