import type { BlockSqlContext } from "../context.ts";
import type { ManufacturingSql } from "./manufacturing-sql.ts";

import { sqlString } from "../../core/template.ts";
import { fail, userGrant } from "../shared.ts";
import { DEFAULT_INSPECTION_KINDS } from "./inspections-values.ts";
import { linked, manufacturingSql } from "./manufacturing-sql.ts";
import { BOM_MAX_DEPTH } from "./manufacturing-values.ts";

const DEPTH = String(BOM_MAX_DEPTH);

/** The JSON of a bill of materials with its components and operations. */
function bomDetail(q: ManufacturingSql, row: string): string {
  const { b, c, o } = q;

  return `(${q.bomJson(row)} || jsonb_build_object(
    'components', coalesce((select jsonb_agg(jsonb_build_object('id', y.${c("id")}, 'variantId', y.${c("variant")}, 'quantity', y.${c("quantity")}::text,
      'scrapBps', y.${c("scrapBps")}, 'operationId', y.${c("operation")}, 'position', y.${c("position")}) order by y.${c("position")}, y.${c("id")})
      from ${q.components} y where y.${c("bom")} = ${row}.${b("id")}), '[]'::jsonb),
    'operations', coalesce((select jsonb_agg(jsonb_build_object('id', y.${o("id")}, 'sequence', y.${o("sequence")}, 'workCenterId', y.${o("workCenter")},
      'title', y.${o("title")}, 'setupMinutes', y.${o("setupMinutes")}::text, 'runMinutesPerUnit', y.${o("runMinutes")}::text,
      'instructionsNodeId', y.${o("instructions")}, 'inspectionTemplate', y.${o("inspectionTemplate")}) order by y.${o("sequence")})
      from ${q.operations} y where y.${o("bom")} = ${row}.${b("id")}), '[]'::jsonb)))`;
}

/** The tenant of a catalog variant, as a SQL expression. */
function variantTenant(q: ManufacturingSql, variant: string): string {
  const v = (column: string): string => q.catalog.col("variants", column);

  return `(select cv.${v("tenant")} from ${q.catalog.table("variants")} cv where cv.${v("id")} = ${variant})`;
}

/** Whether `variant` is a catalog variant of `tenant`. */
export function variantOf(
  q: ManufacturingSql,
  tenant: string,
  variant: string,
): string {
  const v = (column: string): string => q.catalog.col("variants", column);

  return `exists (select 1 from ${q.catalog.table("variants")} cv where cv.${v("id")} = ${variant} and cv.${v("tenant")} = ${tenant})`;
}

export function bomFunctions(ctx: BlockSqlContext): string {
  const q = manufacturingSql(ctx);
  const { fn, b, c, w, o } = q;
  const idType = ctx.idType;
  const inventory = q.inventory;
  const it = (column: string): string => inventory.col("items", column);
  const assets = linked(ctx, "assets");
  const drive = linked(ctx, "drive");

  const inspectionKinds = linked(ctx, "inspections")
    ?.list("kinds", DEFAULT_INSPECTION_KINDS)
    .map((kind) => sqlString(kind))
    .join(", ");

  const assetCheck = assets
    ? `if v_asset is not null and not exists (select 1 from ${assets.table("assets")} a where a.${assets.col("assets", "id")} = v_asset and a.${assets.col("assets", "tenant")} = save_work_center.tenant) then
    ${q.bomInvalid("the asset isn't an asset of this organization")}
  end if;`
    : "";

  const instructionsCheck = drive
    ? `if exists (select 1 from jsonb_array_elements(v_operations) e where nullif(e ->> 'instructionsNodeId', '') is not null
      and not exists (select 1 from ${drive.table("nodes")} d where d.${drive.col("nodes", "id")} = (e ->> 'instructionsNodeId')::uuid and d.${drive.col("nodes", "tenant")} = save_bom.tenant)) then
    ${q.bomInvalid("an operation's instructions aren't a drive node of this organization")}
  end if;`
    : "";

  const templateCheck =
    inspectionKinds === undefined
      ? ""
      : `if exists (select 1 from jsonb_array_elements(v_operations) e where nullif(e ->> 'inspectionTemplate', '') is not null
      and not (e ->> 'inspectionTemplate') in (${inspectionKinds})) then
    ${q.bomInvalid("an operation's inspection template isn't one of the inspection kinds")}
  end if;`;

  return `
-- A quantity of a variant rounded up to the variant's stock scale, so planned
-- component quantities are quantities stock can move.
create or replace function ${fn("production_quantity")}(variant uuid, quantity numeric)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select round(ceil(production_quantity.quantity * power(10::numeric, s.scale)) / power(10::numeric, s.scale), s.scale)
  from (select coalesce((select x.${it("scale")} from ${inventory.table("items")} x where x.${it("variant")} = production_quantity.variant), 0) as scale) s;
$$;
revoke execute on function ${fn("production_quantity")}(uuid, numeric) from public, anon, authenticated;

-- Whether the active bills of materials of variant reach target, at any level.
create or replace function ${fn("bom_reaches")}(variant uuid, target uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  with recursive walk(variant, depth) as (
    select bom_reaches.variant, 0
    union
    select y.${c("variant")}, walk.depth + 1
    from walk
    join ${q.boms} x on x.${b("variant")} = walk.variant and x.${b("status")} = 'active'
    join ${q.components} y on y.${c("bom")} = x.${b("id")}
    where walk.depth < ${DEPTH}
  )
  select exists (select 1 from walk where walk.variant = bom_reaches.target and walk.depth > 0);
$$;
revoke execute on function ${fn("bom_reaches")}(uuid, uuid) from public, anon, authenticated;

-- Creates a draft version of a variant's bill of materials (bom_id null) or
-- replaces a draft's. input is { quantity, note, operations: [{ sequence,
-- workCenterId, title, setupMinutes, runMinutesPerUnit, instructionsNodeId,
-- inspectionTemplate }], components: [{ variantId, quantity, scrapBps,
-- operation }] }; a component's operation is the sequence of the operation
-- that uses it.
create or replace function ${fn("save_bom")}(tenant ${idType}, variant uuid, input jsonb, bom_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${q.boms};
  v_components jsonb;
  v_operations jsonb;
  v_quantity numeric;
begin
  if not ${q.allowed("save_bom.tenant", q.write)} then
    ${q.forbidden("not allowed to change bills of materials")}
  end if;
  if jsonb_typeof(save_bom.input) is distinct from 'object' then
    ${q.bomInvalid("input must be an object")}
  end if;
  if not ${variantOf(q, "save_bom.tenant", "save_bom.variant")} then
    ${q.bomInvalid("the variant isn't a variant of this organization")}
  end if;
  v_quantity := coalesce(nullif(save_bom.input ->> 'quantity', '')::numeric, 1);
  if v_quantity <= 0 then
    ${q.bomInvalid("the quantity must be more than zero")}
  end if;
  v_components := save_bom.input -> 'components';
  v_operations := coalesce(save_bom.input -> 'operations', '[]'::jsonb);
  if jsonb_typeof(v_components) is distinct from 'array' or jsonb_array_length(v_components) = 0 then
    ${q.bomInvalid("a bill of materials lists at least one component")}
  end if;
  if jsonb_typeof(v_operations) <> 'array' then
    ${q.bomInvalid("operations must be an array")}
  end if;
  if exists (select 1 from jsonb_array_elements(v_components) e
    where jsonb_typeof(e) <> 'object' or nullif(e ->> 'variantId', '') is null
      or coalesce(nullif(e ->> 'quantity', '')::numeric, 0) <= 0
      or coalesce(nullif(e ->> 'scrapBps', '')::integer, 0) not between 0 and 10000) then
    ${q.bomInvalid("each component names a variant, a quantity above zero and scrapBps from 0 to 10000")}
  end if;
  if exists (select 1 from jsonb_array_elements(v_components) e where (e ->> 'variantId')::uuid = save_bom.variant) then
    ${fail("BOM_CYCLE", "a variant can't be a component of itself", "22023")}
  end if;
  if exists (select 1 from jsonb_array_elements(v_components) e where not ${variantOf(q, "save_bom.tenant", "(e ->> 'variantId')::uuid")}) then
    ${q.bomInvalid("a component isn't a variant of this organization")}
  end if;
  if exists (select 1 from jsonb_array_elements(v_operations) e
    where jsonb_typeof(e) <> 'object' or coalesce(nullif(e ->> 'sequence', '')::integer, 0) <= 0
      or length(coalesce(trim(e ->> 'title'), '')) not between 1 and 200
      or coalesce(nullif(e ->> 'setupMinutes', '')::numeric, 0) < 0
      or coalesce(nullif(e ->> 'runMinutesPerUnit', '')::numeric, 0) < 0)
    or (select count(distinct e ->> 'sequence') from jsonb_array_elements(v_operations) e) <> jsonb_array_length(v_operations) then
    ${q.bomInvalid("each operation has a unique sequence above zero, a title and minutes of zero or more")}
  end if;
  if exists (select 1 from jsonb_array_elements(v_operations) e
    where not exists (select 1 from ${q.workCenters} x where x.${w("id")} = nullif(e ->> 'workCenterId', '')::uuid
      and x.${w("tenant")} = save_bom.tenant and x.${w("archivedAt")} is null)) then
    ${q.workCenterMissing}
  end if;
  if exists (select 1 from jsonb_array_elements(v_components) e where nullif(e ->> 'operation', '') is not null
    and not exists (select 1 from jsonb_array_elements(v_operations) p where (p ->> 'sequence')::integer = (e ->> 'operation')::integer)) then
    ${q.bomInvalid("a component names an operation sequence the bill of materials doesn't have")}
  end if;
  ${instructionsCheck}
  ${templateCheck}

  if save_bom.bom_id is null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bom:' || save_bom.variant::text, 0));
    insert into ${q.boms} (${b("tenant")}, ${b("variant")}, ${b("version")}, ${b("quantity")}, ${b("note")}, ${b("createdBy")})
    values (save_bom.tenant, save_bom.variant,
      coalesce((select max(x.${b("version")}) from ${q.boms} x where x.${b("variant")} = save_bom.variant), 0) + 1,
      v_quantity, nullif(trim(save_bom.input ->> 'note'), ''), auth.uid())
    returning * into v_row;
  else
    select * into v_row from ${q.boms} x where x.${b("id")} = save_bom.bom_id and x.${b("tenant")} = save_bom.tenant for update;
    if not found then
      ${q.bomMissing}
    end if;
    if v_row.${b("variant")} <> save_bom.variant or v_row.${b("status")} <> 'draft' then
      ${q.bomInvalid("only a draft version of the same variant changes; save a new version instead")}
    end if;
    delete from ${q.components} x where x.${c("bom")} = v_row.${b("id")};
    delete from ${q.operations} x where x.${o("bom")} = v_row.${b("id")};
    update ${q.boms} x set ${b("quantity")} = v_quantity, ${b("note")} = nullif(trim(save_bom.input ->> 'note'), ''), ${b("updatedAt")} = now()
    where x.${b("id")} = v_row.${b("id")}
    returning * into v_row;
  end if;

  insert into ${q.operations} (${o("tenant")}, ${o("bom")}, ${o("sequence")}, ${o("workCenter")}, ${o("title")}, ${o("setupMinutes")}, ${o("runMinutes")}, ${o("instructions")}, ${o("inspectionTemplate")})
  select save_bom.tenant, v_row.${b("id")}, (e ->> 'sequence')::integer, (e ->> 'workCenterId')::uuid, trim(e ->> 'title'),
    coalesce(nullif(e ->> 'setupMinutes', '')::numeric, 0), coalesce(nullif(e ->> 'runMinutesPerUnit', '')::numeric, 0),
    nullif(e ->> 'instructionsNodeId', '')::uuid, nullif(e ->> 'inspectionTemplate', '')
  from jsonb_array_elements(v_operations) e;
  insert into ${q.components} (${c("tenant")}, ${c("bom")}, ${c("position")}, ${c("variant")}, ${c("quantity")}, ${c("scrapBps")}, ${c("operation")})
  select save_bom.tenant, v_row.${b("id")}, e.n::integer, (e.value ->> 'variantId')::uuid, (e.value ->> 'quantity')::numeric,
    coalesce(nullif(e.value ->> 'scrapBps', '')::integer, 0),
    (select y.${o("id")} from ${q.operations} y where y.${o("bom")} = v_row.${b("id")} and y.${o("sequence")} = nullif(e.value ->> 'operation', '')::integer)
  from jsonb_array_elements(v_components) with ordinality e(value, n);
  return ${bomDetail(q, "v_row")};
end;
$$;
${userGrant(`${fn("save_bom")}(${idType}, uuid, jsonb, uuid)`)}

-- Makes a version its variant's active bill of materials; the version that was
-- active is archived. Refuses with BOM_CYCLE when the variant would end up in
-- its own components.
create or replace function ${fn("activate_bom")}(bom_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${q.boms};
begin
  select * into v_row from ${q.boms} x where x.${b("id")} = activate_bom.bom_id for update;
  if not found then
    ${q.bomMissing}
  end if;
  if not ${q.allowed(`v_row.${b("tenant")}`, q.manage)} then
    ${q.forbidden("not allowed to activate bills of materials")}
  end if;
  if v_row.${b("status")} = 'active' then
    return ${bomDetail(q, "v_row")};
  end if;
  if exists (select 1 from ${q.components} y where y.${c("bom")} = v_row.${b("id")}
    and ${fn("bom_reaches")}(y.${c("variant")}, v_row.${b("variant")})) then
    ${fail("BOM_CYCLE", "a component is made from the variant itself", "22023")}
  end if;
  update ${q.boms} x set ${b("status")} = 'archived', ${b("updatedAt")} = now()
  where x.${b("variant")} = v_row.${b("variant")} and x.${b("status")} = 'active';
  update ${q.boms} x set ${b("status")} = 'active', ${b("activatedAt")} = now(), ${b("updatedAt")} = now()
  where x.${b("id")} = v_row.${b("id")}
  returning * into v_row;
  ${q.recordBom("bom.activated", "v_row", "bill of materials activated")}
  return ${bomDetail(q, "v_row")};
end;
$$;
${userGrant(`${fn("activate_bom")}(uuid)`)}

-- A bill of materials version with its components and operations.
create or replace function ${fn("get_bom")}(bom_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row ${q.boms};
begin
  select * into v_row from ${q.boms} x where x.${b("id")} = get_bom.bom_id;
  if not found or not ${q.allowed(`v_row.${b("tenant")}`, q.read)} then
    ${q.bomMissing}
  end if;
  return ${bomDetail(q, "v_row")};
end;
$$;
${userGrant(`${fn("get_bom")}(uuid)`)}

-- The organization's bill of materials versions, of one variant when variant
-- isn't null, the latest version first.
create or replace function ${fn("list_boms")}(tenant ${idType}, variant uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ${q.allowed("list_boms.tenant", q.read)} then
    ${q.forbidden("not allowed to read bills of materials")}
  end if;
  return coalesce((select jsonb_agg(${q.bomJson("x")} order by x.${b("variant")}, x.${b("version")} desc)
    from ${q.boms} x where x.${b("tenant")} = list_boms.tenant
      and (list_boms.variant is null or x.${b("variant")} = list_boms.variant)), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_boms")}(${idType}, uuid)`)}

-- What making quantity of a variant takes, through the active bills of
-- materials at every level: { variantId, quantity, lines: [{ level,
-- variantId, parentVariantId, bomId, quantity, made }], materials: [{
-- variantId, quantity }] }. Planned scrap counts; materials are the lines no
-- active bill of materials makes. Refuses with BOM_NOT_ACTIVE when the
-- variant has no active bill of materials.
create or replace function ${fn("explode_bom")}(variant_id uuid, quantity numeric)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant ${idType} := ${variantTenant(q, "explode_bom.variant_id")};
  v_lines jsonb;
begin
  if v_tenant is null or not ${q.allowed("v_tenant", q.read)} then
    ${q.bomMissing}
  end if;
  if explode_bom.quantity is null or explode_bom.quantity <= 0 then
    ${q.bomInvalid("the quantity must be more than zero")}
  end if;
  if not exists (select 1 from ${q.boms} x where x.${b("variant")} = explode_bom.variant_id and x.${b("status")} = 'active') then
    ${fail("BOM_NOT_ACTIVE", "the variant has no active bill of materials", "55000")}
  end if;
  with recursive tree(variant, parent, bom, quantity, level, path) as (
    select y.${c("variant")}, x.${b("variant")}, x.${b("id")},
      explode_bom.quantity * y.${c("quantity")} / x.${b("quantity")} * (1 + y.${c("scrapBps")} / 10000.0), 1,
      array[x.${b("variant")}, y.${c("variant")}]
    from ${q.boms} x join ${q.components} y on y.${c("bom")} = x.${b("id")}
    where x.${b("variant")} = explode_bom.variant_id and x.${b("status")} = 'active'
    union all
    select y.${c("variant")}, x.${b("variant")}, x.${b("id")},
      tree.quantity * y.${c("quantity")} / x.${b("quantity")} * (1 + y.${c("scrapBps")} / 10000.0), tree.level + 1,
      tree.path || y.${c("variant")}
    from tree
    join ${q.boms} x on x.${b("variant")} = tree.variant and x.${b("status")} = 'active'
    join ${q.components} y on y.${c("bom")} = x.${b("id")}
    where tree.level < ${DEPTH} and not (y.${c("variant")} = any (tree.path))
  )
  select coalesce(jsonb_agg(jsonb_build_object('level', t.level, 'variantId', t.variant, 'parentVariantId', t.parent, 'bomId', t.bom,
      'quantity', ${fn("production_quantity")}(t.variant, t.quantity)::text,
      'made', exists (select 1 from ${q.boms} z where z.${b("variant")} = t.variant and z.${b("status")} = 'active'))
    order by t.path), '[]'::jsonb)
  into v_lines from tree t;
  return jsonb_build_object('variantId', explode_bom.variant_id, 'quantity', explode_bom.quantity::text, 'lines', v_lines,
    'materials', coalesce((select jsonb_agg(jsonb_build_object('variantId', m.variant, 'quantity', m.quantity::text) order by m.variant)
      from (select (e ->> 'variantId')::uuid as variant, sum((e ->> 'quantity')::numeric) as quantity
        from jsonb_array_elements(v_lines) e where not (e ->> 'made')::boolean group by 1) m), '[]'::jsonb));
end;
$$;
${userGrant(`${fn("explode_bom")}(uuid, numeric)`)}

-- The bills of materials a variant goes into: directly in any version that
-- isn't archived (level 1), then up through active versions. Each row is {
-- level, bomId, variantId, version, status, quantity }.
create or replace function ${fn("bom_where_used")}(variant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant ${idType} := ${variantTenant(q, "bom_where_used.variant_id")};
begin
  if v_tenant is null or not ${q.allowed("v_tenant", q.read)} then
    ${q.bomMissing}
  end if;
  return coalesce((with recursive used(bom, variant, version, status, quantity, level, path) as (
    select x.${b("id")}, x.${b("variant")}, x.${b("version")}, x.${b("status")}, y.${c("quantity")}, 1, array[y.${c("variant")}, x.${b("variant")}]
    from ${q.components} y join ${q.boms} x on x.${b("id")} = y.${c("bom")}
    where y.${c("variant")} = bom_where_used.variant_id and x.${b("status")} <> 'archived'
    union all
    select x.${b("id")}, x.${b("variant")}, x.${b("version")}, x.${b("status")}, y.${c("quantity")}, used.level + 1, used.path || x.${b("variant")}
    from used
    join ${q.components} y on y.${c("variant")} = used.variant
    join ${q.boms} x on x.${b("id")} = y.${c("bom")} and x.${b("status")} = 'active'
    where used.status = 'active' and used.level < ${DEPTH} and not (x.${b("variant")} = any (used.path))
  )
  select jsonb_agg(jsonb_build_object('level', u.level, 'bomId', u.bom, 'variantId', u.variant, 'version', u.version,
    'status', u.status, 'quantity', u.quantity::text) order by u.level, u.variant, u.version desc) from used u), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("bom_where_used")}(uuid)`)}

-- Creates a work center (work_center_id null) or changes one. input is {
-- name, assetId, hoursPerDay, costRate (minor units per hour), currency,
-- archived }; keys left out keep their value.
create or replace function ${fn("save_work_center")}(tenant ${idType}, input jsonb, work_center_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${q.workCenters};
  v_asset uuid;
begin
  if not ${q.allowed("save_work_center.tenant", q.manage)} then
    ${q.forbidden("not allowed to change work centers")}
  end if;
  if jsonb_typeof(save_work_center.input) is distinct from 'object' then
    ${q.bomInvalid("input must be an object")}
  end if;
  if save_work_center.work_center_id is not null then
    select * into v_row from ${q.workCenters} x
    where x.${w("id")} = save_work_center.work_center_id and x.${w("tenant")} = save_work_center.tenant for update;
    if not found then
      ${q.workCenterMissing}
    end if;
  end if;
  v_asset := case when save_work_center.input ? 'assetId' then nullif(save_work_center.input ->> 'assetId', '')::uuid else v_row.${w("asset")} end;
  ${assetCheck}
  if save_work_center.work_center_id is null then
    insert into ${q.workCenters} (${w("tenant")}, ${w("name")}, ${w("asset")}, ${w("hoursPerDay")}, ${w("costRate")}, ${w("currency")})
    values (save_work_center.tenant, trim(save_work_center.input ->> 'name'), v_asset,
      coalesce(nullif(save_work_center.input ->> 'hoursPerDay', '')::numeric, 8),
      coalesce(nullif(save_work_center.input ->> 'costRate', '')::bigint, 0),
      upper(nullif(save_work_center.input ->> 'currency', '')))
    returning * into v_row;
  else
    update ${q.workCenters} x set
      ${w("name")} = case when save_work_center.input ? 'name' then trim(save_work_center.input ->> 'name') else x.${w("name")} end,
      ${w("asset")} = v_asset,
      ${w("hoursPerDay")} = coalesce(nullif(save_work_center.input ->> 'hoursPerDay', '')::numeric, x.${w("hoursPerDay")}),
      ${w("costRate")} = coalesce(nullif(save_work_center.input ->> 'costRate', '')::bigint, x.${w("costRate")}),
      ${w("currency")} = case when save_work_center.input ? 'currency' then upper(nullif(save_work_center.input ->> 'currency', '')) else x.${w("currency")} end,
      ${w("archivedAt")} = case when not save_work_center.input ? 'archived' then x.${w("archivedAt")}
        when (save_work_center.input ->> 'archived')::boolean then coalesce(x.${w("archivedAt")}, now()) else null end,
      ${w("updatedAt")} = now()
    where x.${w("id")} = v_row.${w("id")}
    returning * into v_row;
  end if;
  return ${q.workCenterJson("v_row")};
end;
$$;
${userGrant(`${fn("save_work_center")}(${idType}, jsonb, uuid)`)}

-- The organization's work centers by name, archived ones included.
create or replace function ${fn("list_work_centers")}(tenant ${idType})
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ${q.allowed("list_work_centers.tenant", q.read)} then
    ${q.forbidden("not allowed to read work centers")}
  end if;
  return coalesce((select jsonb_agg(${q.workCenterJson("x")} order by x.${w("name")}, x.${w("id")})
    from ${q.workCenters} x where x.${w("tenant")} = list_work_centers.tenant), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_work_centers")}(${idType})`)}
`;
}
