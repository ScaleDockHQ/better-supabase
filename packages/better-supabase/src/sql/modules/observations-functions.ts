import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import {
  extraFieldsArg,
  extraFieldsJson,
  fail,
  raise,
  SERVICE_CALLER,
  serviceGrant,
  userGrant,
  writeExtraColumns,
} from "../shared.ts";
import { subjectInTenant, subjectTenant } from "../subject-check-sql.ts";
import {
  OBSERVATION_RESERVED,
  optionalField,
  sqlList,
  VALUE_TYPES,
} from "./observations-shared.ts";
import { moduleOperations } from "./permissions-model.ts";

/** The most observations one batch call takes. */
const MAX_BATCH = 500;

/** The most components a definition has. */
const MAX_COMPONENTS = 20;

/** The range bounds a definition and each component take. */
const BOUNDS = [
  ["validLow", "validHigh"],
  ["referenceLow", "referenceHigh"],
  ["criticalLow", "criticalHigh"],
] as const;

/** The JSON of definition row `row`. */
export function definitionJson(ctx: BlockSqlContext, row: string): string {
  const d = (column: string): string =>
    `${row}.${ctx.col("definitions", column)}`;

  const field = (column: string): string =>
    optionalField(ctx, "definitions", row, column);

  return `jsonb_build_object('id', ${d("id")}, 'organizationId', ${d("tenant")}, 'system', ${d("tenant")} is null, 'key', ${d("key")}, 'title', ${d("title")}, 'valueType', ${d("valueType")}, 'unit', ${d("unit")}, 'codeSystem', ${d("codeSystem")}, 'code', ${d("code")}, 'components', coalesce(${d("components")}, '[]'::jsonb), 'decimals', ${d("decimals")}, 'validLow', ${d("validLow")}, 'validHigh', ${d("validHigh")}, 'referenceLow', ${d("referenceLow")}, 'referenceHigh', ${d("referenceHigh")}, 'criticalLow', ${d("criticalLow")}, 'criticalHigh', ${d("criticalHigh")}, 'archivedAt', ${d("archivedAt")}, 'createdAt', ${field("createdAt")}, 'updatedAt', ${field("updatedAt")})`;
}

/**
 * The value of observation `row` as JSON, by the value type of its definition
 * row `def`: a number, a boolean, a string or an object of components.
 */
export function observationValue(
  ctx: BlockSqlContext,
  row: string,
  def: string,
): string {
  const o = (column: string): string =>
    `${row}.${ctx.col("observations", column)}`;

  return `case ${def}.${ctx.col("definitions", "valueType")}
      when 'boolean' then to_jsonb(${o("valueCode")} = 'true')
      when 'code' then to_jsonb(${o("valueCode")})
      when 'text' then to_jsonb(${o("valueText")})
      when 'components' then ${o("components")}
      else to_jsonb(${o("valueNumber")})
    end`;
}

/** The JSON of observation `row` with its definition row `def`. */
export function observationJson(
  ctx: BlockSqlContext,
  row: string,
  def: string,
): string {
  const o = (column: string): string =>
    `${row}.${ctx.col("observations", column)}`;

  const field = (column: string): string =>
    optionalField(ctx, "observations", row, column);

  const d = (column: string): string =>
    `${def}.${ctx.col("definitions", column)}`;

  const extras = ctx.extraColumns("observations", OBSERVATION_RESERVED);

  return `jsonb_build_object('id', ${o("id")}, 'organizationId', ${o("tenant")}, 'definitionId', ${o("definition")}, 'definitionKey', ${d("key")}, 'title', ${d("title")}, 'valueType', ${d("valueType")}, 'unit', ${d("unit")}, 'subjectType', ${o("subjectType")}, 'subjectId', ${o("subjectId")}, 'observedAt', ${o("observedAt")}, 'value', ${observationValue(ctx, row, def)}, 'flag', ${o("flag")}, 'status', ${o("status")}, 'replacesId', ${o("replaces")}, 'reason', ${field("reason")}, 'method', ${field("method")}, 'device', ${field("device")}, 'source', ${o("source")}, 'externalId', ${o("externalId")}, 'submissionId', ${o("submission")}, 'performerId', ${o("performer")}, 'note', ${field("note")}, 'createdAt', ${o("createdAt")}${extraFieldsJson(row, extras)})`;
}

/** How far a flag is from normal: 2 for critical, 1 for low or high. */
const severity = (flag: string): string =>
  `(case ${flag} when 'critical_low' then 2 when 'critical_high' then 2 when 'low' then 1 when 'high' then 1 else 0 end)`;

/** The caller checks shared by the write functions. */
export interface ObservationChecks {
  /** True for the service role or a holder of `permission` in `tenant`. */
  readonly allowed: (tenant: string, permission: string) => string;
  /**
   * True when record `type`/`id` is in `tenant` and, for a member, readable
   * through `can_subject`.
   */
  readonly subject: (tenant: string, type: string, id: string) => string;
  readonly forbidden: (message: string) => string;
  readonly invalid: (message: string) => string;
}

export function observationChecks(ctx: BlockSqlContext): ObservationChecks {
  return {
    allowed: (tenant, permission) =>
      `(${SERVICE_CALLER} or ${ctx.can("tenant", tenant, permission)})`,
    subject: (tenant, type, id) =>
      `(case when ${SERVICE_CALLER} then coalesce(${subjectTenant(ctx, type, id)} = ${tenant}::text, false) else ${subjectInTenant(ctx, type, id, tenant)} end)`,
    forbidden: (message) => fail("OBSERVATION_FORBIDDEN", message),
    invalid: (message) => fail("OBSERVATION_INVALID", message, "22023"),
  };
}

/**
 * The internal helpers: the flag of a value, the definition a key names for an
 * organization, and the insert every write goes through.
 */
function internals(ctx: BlockSqlContext): string {
  const definitions = ctx.table("definitions");
  const observations = ctx.table("observations");
  const d = (column: string): string => ctx.col("definitions", column);
  const o = (column: string): string => ctx.col("observations", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const extras = ctx.extraColumns("observations", OBSERVATION_RESERVED);

  const valueInvalid = (message: string): string =>
    fail("OBSERVATION_VALUE_INVALID", message, "22023");

  const invalid = (message: string): string =>
    fail("OBSERVATION_INVALID", message, "22023");

  const has = (column: string): boolean => ctx.has("observations", column);

  const detail = (column: string, max: number): string =>
    `left(nullif(trim(p_details ->> ${sqlString(column)}), ''), ${String(max)})`;

  const insertCols = [
    o("tenant"),
    o("definition"),
    o("subjectType"),
    o("subjectId"),
    o("observedAt"),
    o("valueNumber"),
    o("valueText"),
    o("valueCode"),
    o("components"),
    o("flag"),
    o("replaces"),
    ...(has("method") ? [o("method")] : []),
    ...(has("device") ? [o("device")] : []),
    o("source"),
    o("externalId"),
    o("submission"),
    o("performer"),
    ...(has("note") ? [o("note")] : []),
  ].join(", ");

  const missingDetails = ["method", "device", "note"]
    .filter((column) => !has(column))
    .map(
      (column) => `
  if p_details ? ${sqlString(column)} then
    ${invalid(`the observations table has no ${column} column`)}
  end if;`,
    )
    .join("");

  const insertVals = [
    "p_tenant",
    `v_def.${d("id")}`,
    "p_subject_type",
    "p_subject_id",
    "v_at",
    "v_number",
    "v_text",
    "v_code",
    "v_components",
    "v_flag",
    "p_replaces",
    ...(has("method") ? [detail("method", 200)] : []),
    ...(has("device") ? [detail("device", 200)] : []),
    "p_source",
    "p_external_id",
    "p_submission",
    "p_performer",
    ...(has("note") ? [detail("note", 4000)] : []),
  ].join(", ");

  const record = (
    event: string,
    payload: string,
    summary: string,
    audit: boolean,
  ): string =>
    ctx.record({
      type: event,
      payload: `jsonb_build_object('organizationId', v_row.${o("tenant")}, 'observationId', v_row.${o("id")}, 'definitionKey', v_def.${d("key")}, 'subjectType', v_row.${o("subjectType")}, 'subjectId', v_row.${o("subjectId")}${payload})`,
      subject: `'observations/' || v_row.${o("id")}::text`,
      tenant: `v_row.${o("tenant")}`,
      audit: audit
        ? {
            category: "data",
            targetType: "observation",
            recordId: `v_row.${o("id")}::text`,
            targetLabel: `v_def.${d("title")}`,
            summary,
          }
        : false,
    });

  const notify = ctx.installed("notifications")
    ? (() => {
        const subjects = ctx.of("subjects");
        const m = (column: string): string => subjects.col("members", column);

        return `
    select coalesce(jsonb_agg(distinct m.${m("user")}), '[]'::jsonb) into v_recipients
    from ${subjects.table("members")} m
    where m.${m("subjectType")} = v_row.${o("subjectType")}
      and m.${m("subjectId")} = v_row.${o("subjectId")}
      and m.${m("tenant")}::text = v_row.${o("tenant")}::text
      and m.${m("role")} = 'lead'
      and m.${m("user")} is not null
      and (m.${m("startsOn")} is null or m.${m("startsOn")} <= current_date)
      and (m.${m("endsOn")} is null or m.${m("endsOn")} >= current_date);
    if jsonb_array_length(v_recipients) > 0 then
      ${ctx.notify(
        `jsonb_build_object(
        'type', 'observation.critical',
        'tenant', v_row.${o("tenant")},
        'actor', null,
        'subject_type', v_row.${o("subjectType")},
        'subject_id', v_row.${o("subjectId")},
        'summary', v_def.${d("title")} || ' is ' || replace(v_row.${o("flag")}, '_', ' '),
        'recipients', v_recipients,
        'key', 'observation.critical:' || v_row.${o("id")}::text,
        'data', jsonb_build_object('observationId', v_row.${o("id")}, 'definitionKey', v_def.${d("key")}, 'flag', v_row.${o("flag")})
      )`,
        { indent: "      " },
      )}
    end if;`;
      })()
    : "";

  const component = (key: string): string =>
    `(v_component ->> ${sqlString(key)})::numeric`;

  return `
-- The flag of a value against a range: critical at or past a critical
-- bound, low or high outside the reference range, else normal.
create or replace function ${fn("observation_flag")}(value numeric, reference_low numeric, reference_high numeric, critical_low numeric, critical_high numeric)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when value is null then 'normal'
    when critical_low is not null and value <= critical_low then 'critical_low'
    when critical_high is not null and value >= critical_high then 'critical_high'
    when reference_low is not null and value < reference_low then 'low'
    when reference_high is not null and value > reference_high then 'high'
    else 'normal'
  end
$$;
revoke execute on function ${fn("observation_flag")}(numeric, numeric, numeric, numeric, numeric) from public, anon, authenticated;

-- The definition a key names for an organization: its own, else the system
-- one.
create or replace function ${fn("observation_definition_id")}(p_tenant ${idType}, p_key text)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  select d.${d("id")} into v_id from ${definitions} d
  where d.${d("key")} = p_key and (d.${d("tenant")} = p_tenant or d.${d("tenant")} is null)
  order by d.${d("tenant")} nulls last
  limit 1;
  if v_id is null then
    ${fail("OBSERVATION_DEFINITION_NOT_FOUND", "observation definition not found", "P0002")}
  end if;
  return v_id;
end;
$$;
revoke execute on function ${fn("observation_definition_id")}(${idType}, text) from public, anon, authenticated;

-- Checks a value against its definition, computes the flag and inserts
-- the observation, with its events and the critical alert. Callers check
-- the caller and the record first.
create or replace function ${fn("observation_insert")}(p_tenant ${idType}, p_definition uuid, p_subject_type text, p_subject_id text, p_value jsonb, p_observed_at timestamptz, p_details jsonb, p_source text, p_external_id text, p_submission uuid, p_performer uuid, p_replaces uuid, p_fields jsonb)
returns ${observations}
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_def ${definitions}%rowtype;
  v_row ${observations}%rowtype;
  v_at timestamptz := coalesce(p_observed_at, now());
  v_number numeric;
  v_text text;
  v_code text;
  v_components jsonb;
  v_flag text := 'normal';
  v_component jsonb;
  v_key text;
  v_part numeric;
  v_part_flag text;
  v_recipients jsonb;
  v_claims text;
begin
  select * into v_def from ${definitions} d where d.${d("id")} = p_definition;
  if not found then
    ${fail("OBSERVATION_DEFINITION_NOT_FOUND", "observation definition not found", "P0002")}
  end if;
  if v_def.${d("archivedAt")} is not null then
    ${fail("OBSERVATION_DEFINITION_ARCHIVED", "the observation definition is archived", "22023")}
  end if;
  if v_at > now() + interval '5 minutes' then
    ${invalid("observed_at is in the future")}
  end if;
  if p_details is not null and jsonb_typeof(p_details) <> 'object' then
    ${invalid("details is an object of method, device and note")}
  end if;${missingDetails}
  if p_value is null or jsonb_typeof(p_value) = 'null' then
    ${valueInvalid("an observation needs a value")}
  end if;
  case v_def.${d("valueType")}
    when 'number', 'integer' then
      if jsonb_typeof(p_value) <> 'number' then
        ${raise("%s takes a number", "22023", "OBSERVATION_VALUE_INVALID", `v_def.${d("key")}`)}
      end if;
      v_number := (p_value #>> '{}')::numeric;
      if v_def.${d("valueType")} = 'integer' and v_number <> trunc(v_number) then
        ${valueInvalid("the value is a whole number")}
      end if;
      if v_def.${d("decimals")} is not null then
        v_number := round(v_number, v_def.${d("decimals")});
      end if;
      if v_number < v_def.${d("validLow")} or v_number > v_def.${d("validHigh")} then
        ${valueInvalid("the value is outside the definition's valid range")}
      end if;
      v_flag := ${fn("observation_flag")}(v_number, v_def.${d("referenceLow")}, v_def.${d("referenceHigh")}, v_def.${d("criticalLow")}, v_def.${d("criticalHigh")});
    when 'boolean' then
      if jsonb_typeof(p_value) <> 'boolean' then
        ${valueInvalid("the value is true or false")}
      end if;
      v_code := p_value #>> '{}';
    when 'code' then
      v_code := nullif(trim(p_value #>> '{}'), '');
      if jsonb_typeof(p_value) <> 'string' or v_code is null or length(v_code) > 200 then
        ${valueInvalid("the value is a code of at most 200 characters")}
      end if;
    when 'text' then
      v_text := nullif(trim(p_value #>> '{}'), '');
      if jsonb_typeof(p_value) <> 'string' or v_text is null or length(v_text) > 4000 then
        ${valueInvalid("the value is a text of at most 4000 characters")}
      end if;
    else
      if jsonb_typeof(p_value) <> 'object' then
        ${valueInvalid("the value is an object of components")}
      end if;
      if exists (
        select 1 from jsonb_object_keys(p_value) k
        where not exists (select 1 from jsonb_array_elements(coalesce(v_def.${d("components")}, '[]'::jsonb)) c where c ->> 'key' = k)
      ) then
        ${valueInvalid("the value names a component the definition doesn't have")}
      end if;
      v_components := '{}'::jsonb;
      for v_component in select c from jsonb_array_elements(coalesce(v_def.${d("components")}, '[]'::jsonb)) c loop
        v_key := v_component ->> 'key';
        if not (p_value ? v_key) or jsonb_typeof(p_value -> v_key) = 'null' then
          if coalesce((v_component ->> 'optional')::boolean, false) then
            continue;
          end if;
          ${raise("the value needs the %s component", "22023", "OBSERVATION_VALUE_INVALID", "v_key")}
        end if;
        if jsonb_typeof(p_value -> v_key) <> 'number' then
          ${valueInvalid("each component is a number")}
        end if;
        v_part := (p_value ->> v_key)::numeric;
        if v_component ? 'decimals' then
          v_part := round(v_part, (v_component ->> 'decimals')::integer);
        elsif v_def.${d("decimals")} is not null then
          v_part := round(v_part, v_def.${d("decimals")});
        end if;
        if v_part < ${component("validLow")} or v_part > ${component("validHigh")} then
          ${valueInvalid("a component is outside its valid range")}
        end if;
        v_part_flag := ${fn("observation_flag")}(v_part, ${component("referenceLow")}, ${component("referenceHigh")}, ${component("criticalLow")}, ${component("criticalHigh")});
        if ${severity("v_part_flag")} > ${severity("v_flag")} then
          v_flag := v_part_flag;
        end if;
        v_components := v_components || jsonb_build_object(v_key, v_part);
      end loop;
      if v_components = '{}'::jsonb then
        ${valueInvalid("the value needs at least one component")}
      end if;
  end case;
  if p_replaces is null then
    ${ctx.hook("before_observation_record", [
      [idType, "p_tenant"],
      ["text", "p_subject_type"],
      ["text", "p_subject_id"],
      ["text", `v_def.${d("key")}`],
    ])}
  end if;
  insert into ${observations} (${insertCols})
  values (${insertVals})
  returning * into v_row;${writeExtraColumns(observations, extras, "coalesce(p_fields, '{}'::jsonb)", `x.${o("id")} = v_row.${o("id")}`, "v_row")}
  if p_replaces is null then
    ${record("observation.recorded", `, 'observedAt', v_row.${o("observedAt")}, 'flag', v_row.${o("flag")}, 'source', v_row.${o("source")}`, "'Observation recorded'", true)}
  end if;
  if v_row.${o("flag")} in ('critical_low', 'critical_high') then
    ${record("observation.critical", `, 'observedAt', v_row.${o("observedAt")}, 'flag', v_row.${o("flag")}`, "'Critical observation'", false)}${notify}
  end if;
  if p_replaces is null then
    ${ctx.hook("after_observation_record", [["uuid", `v_row.${o("id")}`]])}
  end if;
  return v_row;
end;
$$;
revoke execute on function ${fn("observation_insert")}(${idType}, uuid, text, text, jsonb, timestamptz, jsonb, text, text, uuid, uuid, uuid, jsonb) from public, anon, authenticated;
`;
}

/** The checks of a definition's ranges in `source` (jsonb), as PL/pgSQL. */
function boundChecks(
  source: string,
  invalid: (message: string) => string,
  what: string,
): string {
  return [
    ...BOUNDS.flat().map(
      (
        key,
      ) => `if ${source} ? ${sqlString(key)} and jsonb_typeof(${source} -> ${sqlString(key)}) not in ('number', 'null') then
    ${invalid(`${what} ${key} is a number`)}
  end if;`,
    ),
    ...BOUNDS.map(
      ([
        low,
        high,
      ]) => `if (${source} ->> ${sqlString(low)})::numeric > (${source} ->> ${sqlString(high)})::numeric then
    ${invalid(`${what} ${low} is at most ${high}`)}
  end if;`,
    ),
  ].join("\n  ");
}

/** The definition and write functions. */
export function observationFunctions(ctx: BlockSqlContext): string {
  const definitions = ctx.table("definitions");
  const observations = ctx.table("observations");
  const d = (column: string): string => ctx.col("definitions", column);
  const o = (column: string): string => ctx.col("observations", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const permissions = moduleOperations("observations");
  const manage = ctx.permission("manage", permissions.manage);
  const recordPermission = ctx.permission("record", permissions.record);
  const extras = ctx.extraColumns("observations", OBSERVATION_RESERVED);
  const extra = extraFieldsArg(extras);
  const { allowed, subject, forbidden, invalid } = observationChecks(ctx);

  const definitionInvalid = (message: string): string =>
    fail("OBSERVATION_DEFINITION_INVALID", message, "22023");

  const notFound = fail(
    "OBSERVATION_NOT_FOUND",
    "observation not found",
    "P0002",
  );

  const definitionNotFound = fail(
    "OBSERVATION_DEFINITION_NOT_FOUND",
    "observation definition not found",
    "P0002",
  );

  const has = (column: string): boolean => ctx.has("definitions", column);

  const touch = has("updatedAt") ? `, ${d("updatedAt")} = now()` : "";

  const definitionRecord = (event: string, summary: string): string =>
    `if v_row.${d("tenant")} is not null then
    ${ctx.record({
      type: event,
      payload: `jsonb_build_object('organizationId', v_row.${d("tenant")}, 'definitionId', v_row.${d("id")}, 'key', v_row.${d("key")}, 'title', v_row.${d("title")})`,
      subject: `'observation-definitions/' || v_row.${d("id")}::text`,
      tenant: `v_row.${d("tenant")}`,
      audit: {
        category: "configuration",
        targetType: "observation_definition",
        recordId: `v_row.${d("id")}::text`,
        targetLabel: `v_row.${d("title")}`,
        summary: `'${summary}'`,
      },
    })}
  end if;`;

  const correction = (
    event: string,
    extraPayload: string,
    summary: string,
  ): string =>
    ctx.record({
      type: event,
      payload: `jsonb_build_object('organizationId', v_row.${o("tenant")}, 'observationId', v_row.${o("id")}, 'definitionKey', v_def.${d("key")}, 'subjectType', v_row.${o("subjectType")}, 'subjectId', v_row.${o("subjectId")}${extraPayload})`,
      subject: `'observations/' || v_row.${o("id")}::text`,
      tenant: `v_row.${o("tenant")}`,
      audit: {
        category: "data",
        targetType: "observation",
        recordId: `v_row.${o("id")}::text`,
        targetLabel: `v_def.${d("title")}`,
        summary: `'${summary}'`,
      },
    });

  const text = (
    source: string,
    key: string,
    max: number,
    message: string,
  ): string => `if ${source} ? ${sqlString(key)} and (jsonb_typeof(${source} -> ${sqlString(key)}) not in ('string', 'null') or length(${source} ->> ${sqlString(key)}) > ${String(max)}) then
    ${definitionInvalid(message)}
  end if;`;

  const setReason = ctx.has("observations", "reason")
    ? (reason: string) => `, ${o("reason")} = ${reason}`
    : () => "";

  // An amendment keeps the details it doesn't change.
  const keptDetails = ["method", "device", "note"]
    .filter((column) => ctx.has("observations", column))
    .map((column) => `${sqlString(column)}, v_old.${o(column)}`)
    .join(", ");

  const details =
    keptDetails === ""
      ? "'{}'::jsonb"
      : `jsonb_strip_nulls(jsonb_build_object(${keptDetails}))`;

  const definitionValues = `v_title, v_type, nullif(trim(v_definition ->> 'unit'), ''), nullif(trim(v_definition ->> 'codeSystem'), ''), nullif(trim(v_definition ->> 'code'), ''), v_components, (v_definition ->> 'decimals')::integer, (v_definition ->> 'validLow')::numeric, (v_definition ->> 'validHigh')::numeric, (v_definition ->> 'referenceLow')::numeric, (v_definition ->> 'referenceHigh')::numeric, (v_definition ->> 'criticalLow')::numeric, (v_definition ->> 'criticalHigh')::numeric`;

  const definitionColumns = [
    "title",
    "valueType",
    "unit",
    "codeSystem",
    "code",
    "components",
    "decimals",
    "validLow",
    "validHigh",
    "referenceLow",
    "referenceHigh",
    "criticalLow",
    "criticalHigh",
  ];

  const definitionSets = [
    ...definitionColumns.map(
      (column) => `${d(column)} = excluded.${d(column)}`,
    ),
    `${d("archivedAt")} = null`,
    ...(has("updatedAt") ? [`${d("updatedAt")} = now()`] : []),
  ].join(",\n      ");

  const itemSubject = (tenant: string): string =>
    subject(tenant, "v_item ->> 'subjectType'", "v_item ->> 'subjectId'");

  const itemInsert = (
    tenant: string,
    source: string,
    externalId: string,
    performer: string,
  ): string =>
    `select * into v_row from ${fn("observation_insert")}(${tenant}, ${fn("observation_definition_id")}(${tenant}, v_item ->> 'definitionKey'), v_item ->> 'subjectType', v_item ->> 'subjectId', v_item -> 'value', (v_item ->> 'observedAt')::timestamptz, v_item -> 'details', ${source}, ${externalId}, null, ${performer}, null, v_item -> 'fields')`;

  const batchCheck = (
    name: string,
  ): string => `if jsonb_typeof(${name}.items) is distinct from 'array' or jsonb_array_length(${name}.items) not between 1 and ${String(MAX_BATCH)} then
    ${invalid(`items is an array of 1 to ${String(MAX_BATCH)} observations`)}
  end if;`;

  const itemCheck = `if jsonb_typeof(v_item) <> 'object' or nullif(v_item ->> 'subjectType', '') is null or nullif(v_item ->> 'subjectId', '') is null or nullif(v_item ->> 'definitionKey', '') is null then
      ${invalid("each item has a subjectType, a subjectId, a definitionKey and a value")}
    end if;`;

  return `${internals(ctx)}
-- Creates or changes an organization's definition with this key; a system
-- definition with the same key stays, and the organization's wins. Only
-- the service role saves system definitions (tenant null).
create or replace function ${fn("save_observation_definition")}(tenant ${idType}, key text, definition jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${definitions}%rowtype;
  v_old ${definitions}%rowtype;
  v_definition jsonb := coalesce(save_observation_definition.definition, '{}'::jsonb);
  v_title text;
  v_type text;
  v_components jsonb;
  v_component jsonb;
begin
  if save_observation_definition.tenant is null then
    if not ${SERVICE_CALLER} then
      ${forbidden("only the service role saves system definitions")}
    end if;
  elsif not ${allowed("save_observation_definition.tenant", manage)} then
    ${forbidden("not allowed to manage observation definitions")}
  end if;
  if save_observation_definition.key is null or save_observation_definition.key !~ '^[a-z][a-z0-9_]{0,62}$' then
    ${definitionInvalid("the key takes lowercase letters, digits and underscores, starting with a letter")}
  end if;
  if jsonb_typeof(v_definition) <> 'object' then
    ${definitionInvalid("definition is an object")}
  end if;
  v_title := nullif(trim(v_definition ->> 'title'), '');
  if v_title is null or length(v_title) > 200 then
    ${definitionInvalid("a definition needs a title of at most 200 characters")}
  end if;
  v_type := v_definition ->> 'valueType';
  if v_type is null or v_type not in ${sqlList(VALUE_TYPES)} then
    ${definitionInvalid(`valueType is one of ${VALUE_TYPES.join(", ")}`)}
  end if;
  ${text("v_definition", "unit", 50, "unit is a UCUM unit of at most 50 characters")}
  ${text("v_definition", "codeSystem", 200, "codeSystem is a text of at most 200 characters")}
  ${text("v_definition", "code", 100, "code is a text of at most 100 characters")}
  if v_definition ? 'decimals' and jsonb_typeof(v_definition -> 'decimals') <> 'null' and (jsonb_typeof(v_definition -> 'decimals') <> 'number' or (v_definition ->> 'decimals')::numeric not in (0, 1, 2, 3, 4, 5, 6)) then
    ${definitionInvalid("decimals is a whole number from 0 to 6")}
  end if;
  ${boundChecks("v_definition", definitionInvalid, "the definition's")}
  v_components := case when jsonb_typeof(v_definition -> 'components') = 'null' then null else v_definition -> 'components' end;
  if v_type = 'components' then
    if jsonb_typeof(v_components) is distinct from 'array' or jsonb_array_length(v_components) not between 1 and ${String(MAX_COMPONENTS)} then
      ${definitionInvalid(`a components definition has 1 to ${String(MAX_COMPONENTS)} components`)}
    end if;
    if (select count(distinct c ->> 'key') from jsonb_array_elements(v_components) c) <> jsonb_array_length(v_components) then
      ${definitionInvalid("component keys are unique")}
    end if;
    for v_component in select c from jsonb_array_elements(v_components) c loop
      if jsonb_typeof(v_component) <> 'object' or coalesce(v_component ->> 'key', '') !~ '^[a-z][a-z0-9_]{0,62}$' then
        ${definitionInvalid("each component has a key of lowercase letters, digits and underscores")}
      end if;
      if nullif(trim(v_component ->> 'title'), '') is null or length(v_component ->> 'title') > 200 then
        ${definitionInvalid("each component has a title of at most 200 characters")}
      end if;
      ${text("v_component", "unit", 50, "a component unit is at most 50 characters")}
      ${text("v_component", "code", 100, "a component code is at most 100 characters")}
      if v_component ? 'decimals' and (jsonb_typeof(v_component -> 'decimals') <> 'number' or (v_component ->> 'decimals')::numeric not in (0, 1, 2, 3, 4, 5, 6)) then
        ${definitionInvalid("a component's decimals is a whole number from 0 to 6")}
      end if;
      if v_component ? 'optional' and jsonb_typeof(v_component -> 'optional') <> 'boolean' then
        ${definitionInvalid("a component's optional is true or false")}
      end if;
      ${boundChecks("v_component", definitionInvalid, "a component's")}
    end loop;
  elsif v_components is not null then
    ${definitionInvalid("only a components definition has components")}
  end if;
  select * into v_old from ${definitions} x
  where x.${d("tenant")} is not distinct from save_observation_definition.tenant and x.${d("key")} = save_observation_definition.key;
  if found and v_old.${d("valueType")} <> v_type and exists (select 1 from ${observations} x where x.${o("definition")} = v_old.${d("id")}) then
    ${definitionInvalid("the value type can't change once observations use the definition")}
  end if;
  ${ctx.hook("before_observation_definition_save", [
    [idType, "save_observation_definition.tenant"],
    ["text", "save_observation_definition.key"],
  ])}
  insert into ${definitions} (${d("tenant")}, ${d("key")}, ${definitionColumns.map(d).join(", ")})
  values (save_observation_definition.tenant, save_observation_definition.key, ${definitionValues})
  on conflict (${d("tenant")}, ${d("key")}) do update set
      ${definitionSets}
  returning * into v_row;
  if v_old.${d("id")} is null then
    ${definitionRecord("observation_definition.created", "Observation definition created")}
  else
    ${definitionRecord("observation_definition.updated", "Observation definition updated")}
  end if;
  ${ctx.hook("after_observation_definition_save", [["uuid", `v_row.${d("id")}`]])}
  return ${definitionJson(ctx, "v_row")};
end;
$$;
${userGrant(`${fn("save_observation_definition")}(${idType}, text, jsonb)`)}

-- Archives a definition: it takes no new observations, and the ones it
-- has stay.
create or replace function ${fn("archive_observation_definition")}(definition_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${definitions}%rowtype;
begin
  select * into v_row from ${definitions} x where x.${d("id")} = archive_observation_definition.definition_id;
  if not found then
    ${definitionNotFound}
  end if;
  if v_row.${d("tenant")} is null then
    if not ${SERVICE_CALLER} then
      ${forbidden("only the service role archives system definitions")}
    end if;
  elsif not ${allowed(`v_row.${d("tenant")}`, manage)} then
    ${forbidden("not allowed to manage observation definitions")}
  end if;
  if v_row.${d("archivedAt")} is null then
    update ${definitions} x set ${d("archivedAt")} = now()${touch}
    where x.${d("id")} = v_row.${d("id")}
    returning x.* into v_row;
    ${definitionRecord("observation_definition.updated", "Observation definition archived")}
  end if;
  return ${definitionJson(ctx, "v_row")};
end;
$$;
${userGrant(`${fn("archive_observation_definition")}(uuid)`)}

-- Records one observation of a record by its definition key. value is a
-- number, true or false, a string, or an object of components; details
-- takes method, device and note.
${extra.drop(fn("record_observation"), `${idType}, text, text, text, jsonb, timestamptz, jsonb`)}
create or replace function ${fn("record_observation")}(tenant ${idType}, subject_type text, subject_id text, definition_key text, value jsonb, observed_at timestamptz default null, details jsonb default null${extra.param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${observations}%rowtype;
  v_def ${definitions}%rowtype;
begin
  if not ${allowed("record_observation.tenant", recordPermission)} then
    ${forbidden("not allowed to record observations")}
  end if;
  if not ${subject("record_observation.tenant", "record_observation.subject_type", "record_observation.subject_id")} then
    ${forbidden("the record isn't in this organization, or you can't read it")}
  end if;
  select * into v_row from ${fn("observation_insert")}(record_observation.tenant, ${fn("observation_definition_id")}(record_observation.tenant, record_observation.definition_key), record_observation.subject_type, record_observation.subject_id, record_observation.value, record_observation.observed_at, record_observation.details, 'manual', null, null, (select auth.uid()), null, ${extras.length > 0 ? "record_observation.fields" : "null"});
  select * into v_def from ${definitions} x where x.${d("id")} = v_row.${o("definition")};
  return ${observationJson(ctx, "v_row", "v_def")};
end;
$$;
${userGrant(`${fn("record_observation")}(${idType}, text, text, text, jsonb, timestamptz, jsonb${extra.type})`)}

-- Records several observations at once (a round of vitals), all or none.
-- Each item takes subjectType, subjectId, definitionKey, value and
-- optionally observedAt, details and fields.
create or replace function ${fn("record_observations")}(tenant ${idType}, items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_item jsonb;
  v_row ${observations}%rowtype;
  v_def ${definitions}%rowtype;
  v_out jsonb := '[]'::jsonb;
begin
  if not ${allowed("record_observations.tenant", recordPermission)} then
    ${forbidden("not allowed to record observations")}
  end if;
  ${batchCheck("record_observations")}
  for v_item in select i from jsonb_array_elements(record_observations.items) i loop
    ${itemCheck}
    if not ${itemSubject("record_observations.tenant")} then
      ${forbidden("the record isn't in this organization, or you can't read it")}
    end if;
    ${itemInsert("record_observations.tenant", "'manual'", "null", "(select auth.uid())")};
    select * into v_def from ${definitions} x where x.${d("id")} = v_row.${o("definition")};
    v_out := v_out || jsonb_build_array(${observationJson(ctx, "v_row", "v_def")});
  end loop;
  return v_out;
end;
$$;
${userGrant(`${fn("record_observations")}(${idType}, jsonb)`)}

-- Ingests readings from a device or an import, as the service role. Each
-- item also takes externalId, which makes it idempotent, and source
-- (device, the default, or import). Returns {inserted, skipped, ids}.
create or replace function ${fn("ingest_observations")}(tenant ${idType}, items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_item jsonb;
  v_row ${observations}%rowtype;
  v_external text;
  v_source text;
  v_ids jsonb := '[]'::jsonb;
  v_skipped integer := 0;
begin
  if not ${SERVICE_CALLER} then
    ${forbidden("only the service role ingests observations")}
  end if;
  ${batchCheck("ingest_observations")}
  for v_item in select i from jsonb_array_elements(ingest_observations.items) i loop
    ${itemCheck}
    v_external := nullif(trim(v_item ->> 'externalId'), '');
    if v_external is null or length(v_external) > 200 then
      ${invalid("each ingested item has an externalId of at most 200 characters")}
    end if;
    v_source := coalesce(v_item ->> 'source', 'device');
    if v_source not in ('device', 'import') then
      ${invalid("source is device or import")}
    end if;
    if not ${itemSubject("ingest_observations.tenant")} then
      ${forbidden("the record isn't in this organization")}
    end if;
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bsb:observations:' || ingest_observations.tenant::text || ':' || v_external, 0));
    if exists (select 1 from ${observations} x where x.${o("tenant")} = ingest_observations.tenant and x.${o("externalId")} = v_external) then
      v_skipped := v_skipped + 1;
      continue;
    end if;
    ${itemInsert("ingest_observations.tenant", "v_source", "v_external", "null")};
    v_ids := v_ids || jsonb_build_array(v_row.${o("id")});
  end loop;
  return jsonb_build_object('inserted', jsonb_array_length(v_ids), 'skipped', v_skipped, 'ids', v_ids);
end;
$$;
${serviceGrant(`${fn("ingest_observations")}(${idType}, jsonb)`)}

-- Corrects a final observation: a new observation replaces it (replacesId)
-- and the old one becomes amended with the reason. changes takes value,
-- observedAt, method, device, note and fields; what it leaves out stays.
create or replace function ${fn("amend_observation")}(observation_id uuid, changes jsonb, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_old ${observations}%rowtype;
  v_row ${observations}%rowtype;
  v_def ${definitions}%rowtype;
  v_changes jsonb := coalesce(amend_observation.changes, '{}'::jsonb);
  v_reason text := nullif(trim(amend_observation.reason), '');
begin
  select * into v_old from ${observations} x where x.${o("id")} = amend_observation.observation_id for update;
  if not found then
    ${notFound}
  end if;
  if not (${allowed(`v_old.${o("tenant")}`, recordPermission)} and ${subject(`v_old.${o("tenant")}`, `v_old.${o("subjectType")}`, `v_old.${o("subjectId")}`)}) then
    ${forbidden("not allowed to amend this observation")}
  end if;
  if v_old.${o("status")} <> 'final' then
    ${invalid("only a final observation can be amended")}
  end if;
  if v_reason is null or length(v_reason) > 2000 then
    ${invalid("an amendment needs a reason of at most 2000 characters")}
  end if;
  if jsonb_typeof(v_changes) <> 'object' then
    ${invalid("changes is an object")}
  end if;
  select * into v_def from ${definitions} x where x.${d("id")} = v_old.${o("definition")};
  ${ctx.hook("before_observation_amend", [["uuid", `v_old.${o("id")}`]])}
  update ${observations} x set ${o("status")} = 'amended'${setReason("v_reason")}
  where x.${o("id")} = v_old.${o("id")};
  select * into v_row from ${fn("observation_insert")}(v_old.${o("tenant")}, v_old.${o("definition")}, v_old.${o("subjectType")}, v_old.${o("subjectId")}, coalesce(v_changes -> 'value', ${observationValue(ctx, "v_old", "v_def")}), coalesce((v_changes ->> 'observedAt')::timestamptz, v_old.${o("observedAt")}), ${details} || (v_changes - 'value' - 'observedAt' - 'fields'), v_old.${o("source")}, null, v_old.${o("submission")}, (select auth.uid()), v_old.${o("id")}, to_jsonb(v_old) || coalesce(v_changes -> 'fields', '{}'::jsonb));
  ${correction("observation.amended", `, 'replacesId', v_old.${o("id")}, 'reason', v_reason`, "Observation amended")}
  ${ctx.hook("after_observation_amend", [["uuid", `v_row.${o("id")}`]])}
  return ${observationJson(ctx, "v_row", "v_def")};
end;
$$;
${userGrant(`${fn("amend_observation")}(uuid, jsonb, text)`)}

-- Marks a final observation entered in error, with the reason. It leaves
-- series and the latest values; marking it again changes nothing.
create or replace function ${fn("mark_observation_error")}(observation_id uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${observations}%rowtype;
  v_def ${definitions}%rowtype;
  v_reason text := nullif(trim(mark_observation_error.reason), '');
begin
  select * into v_row from ${observations} x where x.${o("id")} = mark_observation_error.observation_id for update;
  if not found then
    ${notFound}
  end if;
  if not (${allowed(`v_row.${o("tenant")}`, recordPermission)} and ${subject(`v_row.${o("tenant")}`, `v_row.${o("subjectType")}`, `v_row.${o("subjectId")}`)}) then
    ${forbidden("not allowed to correct this observation")}
  end if;
  select * into v_def from ${definitions} x where x.${d("id")} = v_row.${o("definition")};
  if v_row.${o("status")} = 'entered_in_error' then
    return ${observationJson(ctx, "v_row", "v_def")};
  end if;
  if v_row.${o("status")} <> 'final' then
    ${invalid("only a final observation can be marked entered in error")}
  end if;
  if v_reason is null or length(v_reason) > 2000 then
    ${invalid("marking an observation entered in error needs a reason of at most 2000 characters")}
  end if;
  ${ctx.hook("before_observation_mark_error", [["uuid", `v_row.${o("id")}`]])}
  update ${observations} x set ${o("status")} = 'entered_in_error'${setReason("v_reason")}
  where x.${o("id")} = v_row.${o("id")}
  returning x.* into v_row;
  ${correction("observation.marked_error", ", 'reason', v_reason", "Observation marked entered in error")}
  ${ctx.hook("after_observation_mark_error", [["uuid", `v_row.${o("id")}`]])}
  return ${observationJson(ctx, "v_row", "v_def")};
end;
$$;
${userGrant(`${fn("mark_observation_error")}(uuid, text)`)}
`;
}
