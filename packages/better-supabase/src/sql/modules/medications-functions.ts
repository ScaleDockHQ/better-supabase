import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import {
  fail,
  SERVICE_CALLER,
  serviceGrant,
  userGrant,
  extraFieldsArg,
  writeExtraColumns,
} from "../shared.ts";
import { subjectInTenant } from "../subject-check-sql.ts";
import {
  CODE_SYSTEMS,
  medicationJson,
  medicationKeys,
  medicationTimeZone,
  orderJson,
  MEDICATION_EXTRA,
  ORDER_RESERVED,
  ROW_RESERVED,
  signatureCheck,
  orderRecord,
  scheduleCheck,
  sqlList,
} from "./medications-shared.ts";

/** The order fields `attrs` sets, each as a variable the functions declare. */
const ORDER_FIELDS = `
  v_dose numeric;
  v_unit text;
  v_route text;
  v_schedule jsonb;
  v_as_needed boolean;
  v_as_needed_reason text;
  v_max numeric;
  v_starts date;
  v_ends date;
  v_prescriber text;
  v_double boolean;`;

/**
 * PL/pgSQL that reads the order fields from `attrs` (a jsonb expression) into
 * the `ORDER_FIELDS` variables; a missing key keeps `fallback(field)`.
 */
function readOrderFields(
  attrs: string,
  fallback: (field: string) => string,
): string {
  const value = (key: string): string => `(${attrs} -> '${key}')`;

  const pick = (key: string, read: string, field: string): string =>
    `case when ${attrs} ? '${key}' then ${read} else ${fallback(field)} end`;

  const text = (key: string): string =>
    `nullif(trim(${value(key)} #>> '{}'), '')`;

  return `v_dose := ${pick("dose", `(${value("dose")} #>> '{}')::numeric`, "dose")};
  v_unit := ${pick("doseUnit", text("doseUnit"), "doseUnit")};
  v_route := ${pick("route", text("route"), "route")};
  v_schedule := ${pick("schedule", `nullif(${value("schedule")}, 'null'::jsonb)`, "schedule")};
  v_as_needed := coalesce(${pick("asNeeded", `(${value("asNeeded")} #>> '{}')::boolean`, "asNeeded")}, false);
  v_as_needed_reason := ${pick("asNeededReason", text("asNeededReason"), "asNeededReason")};
  v_max := ${pick("maxPerDay", `(${value("maxPerDay")} #>> '{}')::numeric`, "maxPerDay")};
  v_starts := ${pick("startsOn", `(${value("startsOn")} #>> '{}')::date`, "startsOn")};
  v_ends := ${pick("endsOn", `(${value("endsOn")} #>> '{}')::date`, "endsOn")};
  v_prescriber := ${pick("prescriber", text("prescriber"), "prescriber")};
  v_double := coalesce(${pick("requiresDoubleCheck", `(${value("requiresDoubleCheck")} #>> '{}')::boolean`, "requiresDoubleCheck")}, false);`;
}

/** PL/pgSQL that refuses an order whose `ORDER_FIELDS` don't fit together. */
function checkOrderFields(ctx: BlockSqlContext): string {
  const invalid = (message: string): string =>
    fail("MEDICATION_ORDER_INVALID", message, "22023");

  const prescriber = ctx.has("orders", "prescriber")
    ? `
  if v_prescriber is not null and length(v_prescriber) > 300 then
    ${invalid("prescriber is at most 300 characters")}
  end if;`
    : "";

  return `if v_dose is null or v_dose <= 0 then
    ${invalid("an order needs a dose above zero")}
  end if;
  if v_unit is null or length(v_unit) > 50 then
    ${invalid("an order needs a dose unit of at most 50 characters")}
  end if;
  if v_route is not null and length(v_route) > 100 then
    ${invalid("route is at most 100 characters")}
  end if;
  if not v_as_needed and v_schedule is null then
    ${invalid("an order needs a schedule unless it is given as needed")}
  end if;
  ${scheduleCheck("v_schedule")}
  if v_as_needed_reason is not null and length(v_as_needed_reason) > 500 then
    ${invalid("asNeededReason is at most 500 characters")}
  end if;
  if v_max is not null and v_max <= 0 then
    ${invalid("maxPerDay is above zero")}
  end if;
  if v_starts is null then
    ${invalid("an order needs a start date")}
  end if;
  if v_ends is not null and v_ends < v_starts then
    ${invalid("an order ends on or after its start date")}
  end if;${prescriber}`;
}

/** The catalog functions and the order functions. */
export function medicationFunctions(ctx: BlockSqlContext): string {
  const medications = ctx.table("medications");
  const orders = ctx.table("orders");
  const administrations = ctx.table("administrations");
  const m = (column: string): string => ctx.col("medications", column);
  const o = (column: string): string => ctx.col("orders", column);
  const a = (column: string): string => ctx.col("administrations", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const { prescribe } = medicationKeys(ctx);
  const zone = sqlString(medicationTimeZone(ctx));
  const today = `(now() at time zone ${zone})::date`;

  const has = (table: string, column: string): boolean =>
    ctx.has(table, column);

  const insertCol = (table: string, column: string): string =>
    has(table, column) ? `, ${ctx.col(table, column)}` : "";

  const insertVal = (table: string, column: string, value: string): string =>
    has(table, column) ? `, ${value}` : "";

  const touch = (table: string): string =>
    has(table, "updatedAt") ? `, ${ctx.col(table, "updatedAt")} = now()` : "";

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or ${ctx.can("tenant", tenant, permission)})`;

  const forbidden = (message: string): string =>
    fail("MEDICATION_FORBIDDEN", message);

  const invalid = (message: string): string =>
    fail("MEDICATION_INVALID", message, "22023");

  const orderInvalid = (message: string): string =>
    fail("MEDICATION_ORDER_INVALID", message, "22023");

  const medicationNotFound = fail(
    "MEDICATION_NOT_FOUND",
    "medication not found",
    "P0002",
  );

  const orderNotFound = fail(
    "MEDICATION_ORDER_NOT_FOUND",
    "medication order not found",
    "P0002",
  );

  const inactive = fail(
    "MEDICATION_ORDER_INACTIVE",
    "the medication order is stopped",
    "22023",
  );

  const reasonRequired = fail(
    "MEDICATION_REASON_REQUIRED",
    "stopping an order needs a reason",
    "22023",
  );

  /** Removes the planned doses after now, which planning makes again. */
  const dropPlanned = `delete from ${administrations} x where x.${a("order")} = v_row.${o("id")} and x.${a("status")} = 'planned' and x.${a("scheduledAt")} > now();`;

  const optionalSets = (logical: string, sets: readonly string[]): string =>
    sets.filter((set) => set !== "").join(`,\n    `) +
    (has(logical, "updatedAt")
      ? `,\n    ${ctx.col(logical, "updatedAt")} = now()`
      : "");

  const catalogSets = [
    `${m("name")} = v_name`,
    `${m("codeSystem")} = v_system`,
    `${m("code")} = v_code`,
    has("medications", "form") ? `${m("form")} = v_form` : "",
    has("medications", "strength") ? `${m("strength")} = v_strength` : "",
    `${m("unit")} = v_med_unit`,
    `${m("highRisk")} = v_high_risk`,
  ];

  const itemSets = optionalSets("medications", catalogSets);

  const medicationSets = optionalSets("medications", [
    ...catalogSets,
    `${m("archivedAt")} = null`,
  ]);

  const orderSets = optionalSets("orders", [
    `${o("dose")} = v_dose`,
    `${o("doseUnit")} = v_unit`,
    `${o("route")} = v_route`,
    `${o("schedule")} = v_schedule`,
    `${o("asNeeded")} = v_as_needed`,
    `${o("asNeededReason")} = v_as_needed_reason`,
    `${o("maxPerDay")} = v_max`,
    `${o("startsOn")} = v_starts`,
    `${o("endsOn")} = v_ends`,
    has("orders", "prescriber") ? `${o("prescriber")} = v_prescriber` : "",
    `${o("requiresDoubleCheck")} = v_double`,
  ]);

  const medicationChecks = `if v_name is null or length(v_name) > 300 then
    ${invalid("a medication needs a name of at most 300 characters")}
  end if;
  if v_med_unit is null or length(v_med_unit) > 50 then
    ${invalid("a medication needs a unit of at most 50 characters")}
  end if;
  if v_system is null or v_system not in ${sqlList(CODE_SYSTEMS)} then
    ${invalid("code_system is gtin, hpk, atc, rxnorm or custom")}
  end if;
  if v_code is not null and length(v_code) > 100 then
    ${invalid("a code is at most 100 characters")}
  end if;
  if v_system <> 'custom' and v_code is null then
    ${invalid("a medication from a catalog needs its code")}
  end if;
  if coalesce(length(v_form), 0) > 100 or coalesce(length(v_strength), 0) > 100 then
    ${invalid("form and strength are at most 100 characters")}
  end if;`;

  /**
   * PL/pgSQL that stores catalog item `item` (jsonb) in `tenant`'s catalog,
   * matched on its code, into `v_medication`.
   */
  const storeItem = (
    tenant: string,
    item: string,
  ): string => `v_name := nullif(trim(${item} ->> 'name'), '');
  v_med_unit := nullif(trim(${item} ->> 'unit'), '');
  v_system := coalesce(nullif(trim(${item} ->> 'codeSystem'), ''), 'custom');
  v_code := nullif(trim(${item} ->> 'code'), '');
  v_form := nullif(trim(${item} ->> 'form'), '');
  v_strength := nullif(trim(${item} ->> 'strength'), '');
  v_high_risk := coalesce((${item} ->> 'highRisk')::boolean, false);
  ${medicationChecks}
  select * into v_medication from ${medications} x
  where x.${m("tenant")} = ${tenant} and x.${m("codeSystem")} = v_system and x.${m("code")} = v_code
  for update;
  if found then
    update ${medications} x set
    ${itemSets}
    where x.${m("id")} = v_medication.${m("id")}
    returning x.* into v_medication;
  else
    insert into ${medications} (${m("tenant")}, ${m("name")}, ${m("codeSystem")}, ${m("code")}${insertCol("medications", "form")}${insertCol("medications", "strength")}, ${m("unit")}, ${m("highRisk")})
    values (${tenant}, v_name, v_system, v_code${insertVal("medications", "form", "v_form")}${insertVal("medications", "strength", "v_strength")}, v_med_unit, v_high_risk)
    returning * into v_medication;
  end if;`;

  const medicationVars = `
  v_name text;
  v_med_unit text;
  v_system text;
  v_code text;
  v_form text;
  v_strength text;
  v_high_risk boolean;`;

  const medicationExtras = ctx.extraColumns(
    "medications",
    ROW_RESERVED,
    MEDICATION_EXTRA,
  );

  const medicationFields = extraFieldsArg(medicationExtras);

  // Stores the prescriber's completed signature on an order as its approval.
  const approveOrderSql = has("orders", "signature")
    ? `
-- Approves an order with the caller's completed signature on it (subject type
-- medication_order, the order's id). Needs the signatures module.
create or replace function ${fn("approve_medication_order")}(order_id uuid, signature_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${orders}%rowtype;
begin
  select * into v_row from ${orders} x where x.${o("id")} = approve_medication_order.order_id for update;
  if not found then
    ${fail("MEDICATION_ORDER_NOT_FOUND", "medication order not found", "P0002")}
  end if;
  if not ${allowed(`v_row.${o("tenant")}`, prescribe)} then
    ${forbidden("not allowed to prescribe medication")}
  end if;
  if approve_medication_order.signature_id is null then
    ${fail("MEDICATION_SIGNATURE_INVALID", "approving an order needs a signature", "22023")}
  end if;
  ${signatureCheck(ctx, {
    signature: "approve_medication_order.signature_id",
    tenant: `v_row.${o("tenant")}`,
    type: "'medication_order'",
    id: `v_row.${o("id")}::text`,
  })}
  update ${orders} x set ${o("signature")} = approve_medication_order.signature_id${touch("orders")}
  where x.${o("id")} = v_row.${o("id")}
  returning x.* into v_row;
  ${orderRecord(ctx, "medication_order.updated", "v_row", "", "Medication order approved")}
  return ${orderJson(ctx, "v_row")};
end;
$$;
${userGrant(`${fn("approve_medication_order")}(uuid, uuid)`)}
`
    : "";

  /** PL/pgSQL that inserts an order from the `ORDER_FIELDS` into `v_row`. */
  const extras = ctx.extraColumns("orders", ORDER_RESERVED);

  /**
   * Refuses `fields` in `attrs` unless it is an object; empty without extra
   * columns.
   */
  const fieldsCheck = (attrs: string): string =>
    extras.length === 0
      ? ""
      : `if ${attrs} ? 'fields' and jsonb_typeof(${attrs} -> 'fields') <> 'object' then
    ${orderInvalid("fields is an object")}
  end if;`;

  /** Copies `attrs.fields` onto the extra columns of order `v_row`. */
  const writeFields = (attrs: string): string =>
    writeExtraColumns(
      orders,
      extras,
      `coalesce(${attrs} -> 'fields', '{}'::jsonb)`,
      `x.${o("id")} = v_row.${o("id")}`,
      "v_row",
    );

  const insertOrder = (options: {
    readonly attrs: string;
    readonly tenant: string;
    readonly subjectType: string;
    readonly subjectId: string;
    readonly medication: string;
    readonly source: string;
    readonly externalId: string;
  }): string => `insert into ${orders} (${o("tenant")}, ${o("subjectType")}, ${o("subjectId")}, ${o("medication")}, ${o("dose")}, ${o("doseUnit")}, ${o("route")}, ${o("schedule")}, ${o("asNeeded")}, ${o("asNeededReason")}, ${o("maxPerDay")}, ${o("startsOn")}, ${o("endsOn")}${insertCol("orders", "prescriber")}, ${o("source")}, ${o("externalId")}, ${o("requiresDoubleCheck")}${insertCol("orders", "createdBy")})
    values (${options.tenant}, ${options.subjectType}, ${options.subjectId}, ${options.medication}, v_dose, v_unit, v_route, v_schedule, v_as_needed, v_as_needed_reason, v_max, v_starts, v_ends${insertVal("orders", "prescriber", "v_prescriber")}, ${options.source}, ${options.externalId}, v_double${insertVal("orders", "createdBy", "(select auth.uid())")})
    returning * into v_row;${writeFields(options.attrs)}`;

  const newFields = (attrs: string, unit: string): string =>
    readOrderFields(attrs, (field) => {
      switch (field) {
        case "doseUnit": {
          return unit;
        }

        case "startsOn": {
          return today;
        }

        default: {
          return "null";
        }
      }
    });

  const rowFields = (attrs: string): string =>
    readOrderFields(attrs, (field) =>
      has("orders", field) ? `v_row.${o(field)}` : "null",
    );

  const subjectCheck = (
    fnName: string,
  ): string => `if not ${subjectInTenant(ctx, `${fnName}.subject_type`, `${fnName}.subject_id`, `${fnName}.tenant`)} then
    ${fail("MEDICATION_ORDER_INVALID", "the record isn't in this organization", "22023")}
  end if;`;

  const created = orderRecord(
    ctx,
    "medication_order.created",
    "v_row",
    "",
    "Medication prescribed",
  );

  return `
-- Adds a medication to the organization's catalog, or changes one
-- (medication_id). A code from a catalog other than custom is unique in the
-- organization.
${medicationFields.drop(fn("save_medication"), `${idType}, text, text, text, text, text, text, boolean, uuid`)}
create or replace function ${fn("save_medication")}(tenant ${idType}, name text, unit text, code_system text default 'custom', code text default null, form text default null, strength text default null, high_risk boolean default false, medication_id uuid default null${medicationFields.param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_medication ${medications}%rowtype;${medicationVars}
begin
  if not ${allowed("save_medication.tenant", prescribe)} then
    ${forbidden("not allowed to change the medication catalog")}
  end if;
  v_name := nullif(trim(save_medication.name), '');
  v_med_unit := nullif(trim(save_medication.unit), '');
  v_system := coalesce(nullif(trim(save_medication.code_system), ''), 'custom');
  v_code := nullif(trim(save_medication.code), '');
  v_form := nullif(trim(save_medication.form), '');
  v_strength := nullif(trim(save_medication.strength), '');
  v_high_risk := coalesce(save_medication.high_risk, false);
  ${medicationChecks}
  if exists (
    select 1 from ${medications} x
    where x.${m("tenant")} = save_medication.tenant and x.${m("codeSystem")} = v_system and x.${m("code")} = v_code
      and x.${m("id")} is distinct from save_medication.medication_id
  ) then
    ${invalid("the catalog already has a medication with this code")}
  end if;
  if save_medication.medication_id is null then
    insert into ${medications} (${m("tenant")}, ${m("name")}, ${m("codeSystem")}, ${m("code")}${insertCol("medications", "form")}${insertCol("medications", "strength")}, ${m("unit")}, ${m("highRisk")})
    values (save_medication.tenant, v_name, v_system, v_code${insertVal("medications", "form", "v_form")}${insertVal("medications", "strength", "v_strength")}, v_med_unit, v_high_risk)
    returning * into v_medication;
  else
    update ${medications} x set
    ${medicationSets}
    where x.${m("id")} = save_medication.medication_id and x.${m("tenant")} = save_medication.tenant
    returning x.* into v_medication;
    if not found then
      ${medicationNotFound}
    end if;
  end if;${writeExtraColumns(medications, medicationExtras, "save_medication.fields", `x.${m("id")} = v_medication.${m("id")}`, "v_medication")}
  return ${medicationJson(ctx, "v_medication")};
end;
$$;
${userGrant(`${fn("save_medication")}(${idType}, text, text, text, text, text, text, boolean, uuid${medicationFields.type})`)}

-- Archives a medication: new orders can't use it; its orders stay.
create or replace function ${fn("archive_medication")}(medication_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_medication ${medications}%rowtype;
begin
  select * into v_medication from ${medications} x where x.${m("id")} = archive_medication.medication_id;
  if not found then
    ${medicationNotFound}
  end if;
  if not ${allowed(`v_medication.${m("tenant")}`, prescribe)} then
    ${forbidden("not allowed to change the medication catalog")}
  end if;
  update ${medications} x set ${m("archivedAt")} = coalesce(x.${m("archivedAt")}, now())${touch("medications")}
  where x.${m("id")} = v_medication.${m("id")}
  returning x.* into v_medication;
  return ${medicationJson(ctx, "v_medication")};
end;
$$;
${userGrant(`${fn("archive_medication")}(uuid)`)}

-- Stores an item picked from a MedicationCatalog (name, unit, codeSystem,
-- code, form, strength, highRisk) in the organization's catalog. An item
-- already there under its code is updated, so picking it twice is safe.
create or replace function ${fn("import_medication")}(tenant ${idType}, item jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_medication ${medications}%rowtype;${medicationVars}
begin
  if not ${allowed("import_medication.tenant", prescribe)} then
    ${forbidden("not allowed to change the medication catalog")}
  end if;
  if import_medication.item is null or jsonb_typeof(import_medication.item) <> 'object' then
    ${invalid("a catalog item is an object")}
  end if;
  ${storeItem("import_medication.tenant", "import_medication.item")}
  return ${medicationJson(ctx, "v_medication")};
end;
$$;
${userGrant(`${fn("import_medication")}(${idType}, jsonb)`)}

create or replace function ${fn("list_medications")}(tenant ${idType}, search text default null, include_archived boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${medicationJson(ctx, "x")} order by x.${m("name")}, x.${m("id")}), '[]'::jsonb)
  from ${medications} x
  where x.${m("tenant")} = list_medications.tenant
    and (coalesce(list_medications.include_archived, false) or x.${m("archivedAt")} is null)
    and (nullif(trim(list_medications.search), '') is null
      or x.${m("name")} ilike '%' || trim(list_medications.search) || '%'
      or x.${m("code")} = trim(list_medications.search))
$$;
${userGrant(`${fn("list_medications")}(${idType}, text, boolean)`)}

-- Prescribes a medication for a record. attrs holds dose, doseUnit (the
-- medication's unit by default), route, schedule, asNeeded, asNeededReason,
-- maxPerDay, startsOn (today by default), endsOn, prescriber,
-- requiresDoubleCheck and fields, the extra columns by name.
create or replace function ${fn("prescribe_medication")}(tenant ${idType}, subject_type text, subject_id text, medication_id uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${orders}%rowtype;
  v_medication ${medications}%rowtype;
  v_attrs jsonb := coalesce(prescribe_medication.attrs, '{}'::jsonb);${ORDER_FIELDS}
begin
  if not ${allowed("prescribe_medication.tenant", prescribe)} then
    ${forbidden("not allowed to prescribe medication")}
  end if;
  ${subjectCheck("prescribe_medication")}
  select * into v_medication from ${medications} x
  where x.${m("id")} = prescribe_medication.medication_id and x.${m("tenant")} = prescribe_medication.tenant and x.${m("archivedAt")} is null;
  if not found then
    ${medicationNotFound}
  end if;
  if jsonb_typeof(v_attrs) <> 'object' then
    ${orderInvalid("attrs is an object")}
  end if;
  ${newFields("v_attrs", `v_medication.${m("unit")}`)}
  ${checkOrderFields(ctx)}
  ${fieldsCheck("v_attrs")}
  ${ctx.hook("before_medication_order_prescribe", [
    [idType, "prescribe_medication.tenant"],
    ["text", "prescribe_medication.subject_type"],
    ["text", "prescribe_medication.subject_id"],
    ["uuid", "prescribe_medication.medication_id"],
  ])}
  ${insertOrder({
    attrs: "v_attrs",
    tenant: "prescribe_medication.tenant",
    subjectType: "prescribe_medication.subject_type",
    subjectId: "prescribe_medication.subject_id",
    medication: `v_medication.${m("id")}`,
    source: "'prescriber'",
    externalId: "null",
  })}
  ${created}
  ${ctx.hook("after_medication_order_prescribe", [["uuid", `v_row.${o("id")}`]])}
  return ${orderJson(ctx, "v_row")};
end;
$$;
${userGrant(`${fn("prescribe_medication")}(${idType}, text, text, uuid, jsonb)`)}

-- Imports orders from a pharmacy or prescribing system. Each item has
-- subjectType, subjectId, externalId, a medicationId or a catalog item under
-- medication, and the order fields prescribe_medication takes. An item whose
-- externalId was imported before is skipped, so the import can run again.
create or replace function ${fn("import_medication_orders")}(tenant ${idType}, items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${orders}%rowtype;
  v_medication ${medications}%rowtype;
  v_item jsonb;
  v_external text;
  v_created jsonb := '[]'::jsonb;
  v_skipped integer := 0;${medicationVars}${ORDER_FIELDS}
begin
  if import_medication_orders.items is null or jsonb_typeof(import_medication_orders.items) <> 'array' then
    ${orderInvalid("items is an array")}
  end if;
  for v_item in select value from jsonb_array_elements(import_medication_orders.items) loop
    if jsonb_typeof(v_item) <> 'object' then
      ${orderInvalid("each item is an object")}
    end if;
    v_external := nullif(trim(v_item ->> 'externalId'), '');
    if v_external is null then
      ${orderInvalid("each imported order needs an externalId")}
    end if;
    if exists (select 1 from ${orders} x where x.${o("tenant")} = import_medication_orders.tenant and x.${o("externalId")} = v_external) then
      v_skipped := v_skipped + 1;
      continue;
    end if;
    if not ${subjectInTenant(ctx, "(v_item ->> 'subjectType')", "(v_item ->> 'subjectId')", "import_medication_orders.tenant")} then
      ${orderInvalid("the record isn't in this organization")}
    end if;
    if jsonb_typeof(v_item -> 'medication') = 'object' then
      ${storeItem("import_medication_orders.tenant", "(v_item -> 'medication')")}
    else
      select * into v_medication from ${medications} x
      where x.${m("id")} = (v_item ->> 'medicationId')::uuid and x.${m("tenant")} = import_medication_orders.tenant;
      if not found then
        ${medicationNotFound}
      end if;
    end if;
    ${newFields("v_item", `v_medication.${m("unit")}`)}
    ${checkOrderFields(ctx)}
    ${fieldsCheck("v_item")}
    ${insertOrder({
      attrs: "v_item",
      tenant: "import_medication_orders.tenant",
      subjectType: "v_item ->> 'subjectType'",
      subjectId: "v_item ->> 'subjectId'",
      medication: `v_medication.${m("id")}`,
      source: `coalesce(nullif(v_item ->> 'source', ''), 'import')`,
      externalId: "v_external",
    })}
    ${created}
    v_created := v_created || jsonb_build_array(${orderJson(ctx, "v_row")});
  end loop;
  return jsonb_build_object('created', v_created, 'skipped', v_skipped);
end;
$$;
${serviceGrant(`${fn("import_medication_orders")}(${idType}, jsonb)`)}

-- Changes an order's dose, unit, route, schedule, as-needed fields, dates,
-- prescriber, double check or extra columns (fields); a key attrs leaves out
-- keeps its value. The
-- planned doses after now are removed for planning to make again.
create or replace function ${fn("update_medication_order")}(order_id uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${orders}%rowtype;
  v_attrs jsonb := coalesce(update_medication_order.attrs, '{}'::jsonb);${ORDER_FIELDS}
begin
  select * into v_row from ${orders} x where x.${o("id")} = update_medication_order.order_id for update;
  if not found then
    ${orderNotFound}
  end if;
  if not ${allowed(`v_row.${o("tenant")}`, prescribe)} then
    ${forbidden("not allowed to prescribe medication")}
  end if;
  if v_row.${o("status")} = 'stopped' then
    ${inactive}
  end if;
  if jsonb_typeof(v_attrs) <> 'object' then
    ${orderInvalid("attrs is an object")}
  end if;
  ${rowFields("v_attrs")}
  ${checkOrderFields(ctx)}
  ${fieldsCheck("v_attrs")}
  update ${orders} x set
    ${orderSets}
  where x.${o("id")} = v_row.${o("id")}
  returning x.* into v_row;${writeFields("v_attrs")}
  ${dropPlanned}
  ${orderRecord(ctx, "medication_order.updated", "v_row", "", "Medication order changed")}
  return ${orderJson(ctx, "v_row")};
end;
$$;
${userGrant(`${fn("update_medication_order")}(uuid, jsonb)`)}
${approveOrderSql}
-- Pauses an active order (paused true) or resumes a paused one. A paused
-- order gets no planned doses; the ones after now are removed.
create or replace function ${fn("pause_medication_order")}(order_id uuid, paused boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${orders}%rowtype;
  v_status text := case when coalesce(pause_medication_order.paused, true) then 'paused' else 'active' end;
begin
  select * into v_row from ${orders} x where x.${o("id")} = pause_medication_order.order_id for update;
  if not found then
    ${orderNotFound}
  end if;
  if not ${allowed(`v_row.${o("tenant")}`, prescribe)} then
    ${forbidden("not allowed to prescribe medication")}
  end if;
  if v_row.${o("status")} = 'stopped' then
    ${inactive}
  end if;
  if v_row.${o("status")} = v_status then
    return ${orderJson(ctx, "v_row")};
  end if;
  update ${orders} x set ${o("status")} = v_status${touch("orders")}
  where x.${o("id")} = v_row.${o("id")}
  returning x.* into v_row;
  if v_status = 'paused' then
    ${dropPlanned}
    ${orderRecord(ctx, "medication_order.paused", "v_row", "", "Medication order paused")}
  else
    ${orderRecord(ctx, "medication_order.updated", "v_row", "", "Medication order resumed")}
  end if;
  return ${orderJson(ctx, "v_row")};
end;
$$;
${userGrant(`${fn("pause_medication_order")}(uuid, boolean)`)}

-- Stops an order for good, with the reason. The planned doses after now are
-- removed; the doses already recorded stay on the chart.
create or replace function ${fn("stop_medication_order")}(order_id uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${orders}%rowtype;
  v_reason text := nullif(trim(stop_medication_order.reason), '');
begin
  select * into v_row from ${orders} x where x.${o("id")} = stop_medication_order.order_id for update;
  if not found then
    ${orderNotFound}
  end if;
  if not ${allowed(`v_row.${o("tenant")}`, prescribe)} then
    ${forbidden("not allowed to prescribe medication")}
  end if;
  if v_reason is null then
    ${reasonRequired}
  end if;
  if length(v_reason) > 1000 then
    ${orderInvalid("a reason is at most 1000 characters")}
  end if;
  if v_row.${o("status")} = 'stopped' then
    return ${orderJson(ctx, "v_row")};
  end if;
  ${ctx.hook("before_medication_order_stop", [["uuid", `v_row.${o("id")}`]])}
  update ${orders} x set ${o("status")} = 'stopped', ${o("stoppedReason")} = v_reason${touch("orders")}
  where x.${o("id")} = v_row.${o("id")}
  returning x.* into v_row;
  ${dropPlanned}
  ${orderRecord(ctx, "medication_order.stopped", "v_row", ", 'reason', v_reason", "Medication order stopped")}
  ${ctx.hook("after_medication_order_stop", [["uuid", `v_row.${o("id")}`]])}
  return ${orderJson(ctx, "v_row")};
end;
$$;
${userGrant(`${fn("stop_medication_order")}(uuid, text)`)}

create or replace function ${fn("medication_orders_of")}(subject_type text, subject_id text, include_stopped boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${orderJson(ctx, "x")} || jsonb_build_object('medication', ${medicationJson(ctx, "y")}) order by x.${o("startsOn")} desc, x.${o("id")}), '[]'::jsonb)
  from ${orders} x
  join ${medications} y on y.${m("tenant")} = x.${o("tenant")} and y.${m("id")} = x.${o("medication")}
  where x.${o("subjectType")} = medication_orders_of.subject_type
    and x.${o("subjectId")} = medication_orders_of.subject_id
    and (coalesce(medication_orders_of.include_stopped, false) or x.${o("status")} <> 'stopped')
$$;
${userGrant(`${fn("medication_orders_of")}(text, text, boolean)`)}
`;
}
