import type { BlockSqlContext } from "../context.ts";
import type { LimsSql } from "./lims-sql.ts";

import { sqlString } from "../../core/template.ts";
import { assignNumberSql } from "../numbering-sql.ts";
import { pageSize, userGrant } from "../shared.ts";
import { limsSql } from "./lims-sql.ts";

function methodFunctions(ctx: BlockSqlContext, q: LimsSql): string {
  const { fn, m, methods } = q;
  const idType = ctx.idType;

  const methodEvent = (type: string): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', v_row.${m("tenant")}, 'id', v_row.${m("id")}, 'key', v_row.${m("key")})`,
      subject: `'lims-methods/' || v_row.${m("id")}::text`,
      tenant: `v_row.${m("tenant")}`,
      audit: false,
    });

  const formCheck =
    q.forms === undefined
      ? `if v_input ->> 'formId' is not null then
    ${q.invalid("formId needs the forms block")}
  end if;`
      : `if v_input ->> 'formId' is not null and not exists (
    select 1 from ${q.forms.table("forms")} y
    where y.${q.forms.col("forms", "id")} = (v_input ->> 'formId')::uuid
      and y.${q.forms.col("forms", "tenant")}::text = save_lims_method.tenant::text
  ) then
    ${q.invalid("the form is not a form of this organization")}
  end if;`;

  return `
-- Creates or updates a test method: what is measured, its unit and its specification limits.
-- input is { key, name, unit, lowerLimit, upperLimit, formId }; key is
-- lowercase letters, digits and underscores and cannot change once saved.
-- A result below lowerLimit or above upperLimit is out of specification. formId
-- names the form that captures the raw readings. Pass method_id to update.
-- Needs lims.manage.
create or replace function ${fn("save_lims_method")}(tenant ${idType}, input jsonb, method_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${methods};
  v_input jsonb := coalesce(save_lims_method.input, '{}'::jsonb);
  v_created boolean := save_lims_method.method_id is null;
begin
  if not ${q.allowed("save_lims_method.tenant", q.manage)} then
    ${q.forbidden("not allowed to save test methods")}
  end if;
  if jsonb_typeof(v_input) is distinct from 'object' then
    ${q.invalid("input must be an object")}
  end if;
  ${formCheck}
  begin
    if save_lims_method.method_id is null then
      insert into ${methods} (${m("tenant")}, ${m("key")}, ${m("name")}, ${m("unit")}, ${m("lowerLimit")}, ${m("upperLimit")}, ${m("form")})
      values (save_lims_method.tenant, v_input ->> 'key', trim(v_input ->> 'name'), nullif(trim(v_input ->> 'unit'), ''),
        (v_input ->> 'lowerLimit')::numeric, (v_input ->> 'upperLimit')::numeric, (v_input ->> 'formId')::uuid)
      returning * into v_row;
    else
      update ${methods} x set ${m("name")} = trim(v_input ->> 'name'), ${m("unit")} = nullif(trim(v_input ->> 'unit'), ''),
        ${m("lowerLimit")} = (v_input ->> 'lowerLimit')::numeric, ${m("upperLimit")} = (v_input ->> 'upperLimit')::numeric,
        ${m("form")} = (v_input ->> 'formId')::uuid, ${m("updatedAt")} = now()
      where x.${m("id")} = save_lims_method.method_id and x.${m("tenant")} = save_lims_method.tenant
      returning * into v_row;
      if not found then
        ${q.methodMissing}
      end if;
    end if;
  exception when check_violation or not_null_violation or invalid_text_representation or numeric_value_out_of_range then
    ${q.invalid("a method needs a key of lowercase letters, digits and underscores, a name of 1 to 200 characters and a lowerLimit not above the upperLimit")}
  when unique_violation then
    ${q.invalid("this organization already has a method with that key")}
  end;
  if v_created then
    ${methodEvent("lims_method.created")}
  else
    ${methodEvent("lims_method.updated")}
  end if;
  return ${q.methodJson("v_row")};
end;
$$;
${userGrant(`${fn("save_lims_method")}(${idType}, jsonb, uuid)`)}

-- Archives a method so no new result can use it. Its results stay. Needs
-- lims.manage.
create or replace function ${fn("archive_lims_method")}(method_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${methods};
begin
  select * into v_row from ${methods} x where x.${m("id")} = archive_lims_method.method_id for update;
  if not found or not ${q.allowed(`v_row.${m("tenant")}`, q.read)} then
    ${q.methodMissing}
  end if;
  if not ${q.allowed(`v_row.${m("tenant")}`, q.manage)} then
    ${q.forbidden("not allowed to archive test methods")}
  end if;
  update ${methods} x set ${m("archivedAt")} = coalesce(x.${m("archivedAt")}, now()), ${m("updatedAt")} = now()
  where x.${m("id")} = v_row.${m("id")} returning * into v_row;
  ${methodEvent("lims_method.archived")}
  return ${q.methodJson("v_row")};
end;
$$;
${userGrant(`${fn("archive_lims_method")}(uuid)`)}

-- The organization's test methods by key; archived ones only with
-- include_archived.
create or replace function ${fn("list_lims_methods")}(tenant ${idType}, include_archived boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not ${q.allowed("list_lims_methods.tenant", q.read)} then
    ${q.forbidden("not allowed to read test methods")}
  end if;
  return coalesce((
    select jsonb_agg(${q.methodJson("x")} order by x.${m("key")})
    from ${methods} x
    where x.${m("tenant")} = list_lims_methods.tenant
      and (coalesce(list_lims_methods.include_archived, false) or x.${m("archivedAt")} is null)
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_lims_methods")}(${idType}, boolean)`)}
`;
}

function sampleFunctions(ctx: BlockSqlContext, q: LimsSql): string {
  const { fn, s, r, samples, results } = q;
  const idType = ctx.idType;

  const numberAssign = assignNumberSql(
    ctx,
    ctx.naming.rename("lims_sample"),
    "register_sample.tenant",
    { seq: "v_seq", identifier: "v_number" },
    { table: samples, seq: s("sequence"), tenant: s("tenant"), prefix: "SMP-" },
  );

  return `
-- Registers a sample as received and numbers it (SMP-1, or the numbering
-- block's format for lims_sample). input is { title, kind, lot, receivedOn,
-- notes }. Needs lims.write.
create or replace function ${fn("register_sample")}(tenant ${idType}, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${samples};
  v_seq bigint;
  v_number text;
begin
  if not ${q.allowed("register_sample.tenant", q.write)} then
    ${q.forbidden("not allowed to register samples")}
  end if;
  if jsonb_typeof(register_sample.input) is distinct from 'object' then
    ${q.invalid("input must be an object")}
  end if;
  ${ctx.hook("before_lims_sample_register", [
    [idType, "register_sample.tenant"],
    ["jsonb", "register_sample.input"],
  ])}
  ${numberAssign}
  begin
    insert into ${samples} (${s("tenant")}, ${s("number")}, ${s("sequence")}, ${s("title")}, ${s("kind")}, ${s("lot")}, ${s("receivedOn")}, ${s("notes")}, ${s("createdBy")})
    values (register_sample.tenant, v_number, v_seq, trim(register_sample.input ->> 'title'),
      nullif(trim(register_sample.input ->> 'kind'), ''), nullif(trim(register_sample.input ->> 'lot'), ''),
      coalesce((register_sample.input ->> 'receivedOn')::date, current_date),
      nullif(trim(register_sample.input ->> 'notes'), ''), auth.uid())
    returning * into v_row;
  exception when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    ${q.invalid("a sample needs a title of 1 to 200 characters, a kind and lot of up to 100 and notes of up to 4000")}
  end;
  ${q.recordSample("lims_sample.registered", "v_row", "sample registered")}
  ${ctx.hook("after_lims_sample_register", [["uuid", `v_row.${s("id")}`]])}
  return ${q.sampleJson("v_row")};
end;
$$;
${userGrant(`${fn("register_sample")}(${idType}, jsonb)`)}

-- One sample with its results, newest first.
create or replace function ${fn("get_sample")}(sample_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${samples};
begin
  select * into v_row from ${samples} x where x.${s("id")} = get_sample.sample_id;
  if not found or not ${q.allowed(`v_row.${s("tenant")}`, q.read)} then
    ${q.sampleMissing}
  end if;
  return ${q.sampleJson("v_row")} || jsonb_build_object('results', coalesce((
    select jsonb_agg(${q.resultJson("y")} order by y.${r("testedAt")} desc, y.${r("id")})
    from ${results} y where y.${r("sample")} = v_row.${s("id")}
  ), '[]'::jsonb));
end;
$$;
${userGrant(`${fn("get_sample")}(uuid)`)}

-- Samples, newest first. filters is { status, limit, offset }.
create or replace function ${fn("list_samples")}(tenant ${idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_samples.filters, '{}'::jsonb);
  v_limit integer := ${pageSize("(v_filters ->> 'limit')::integer", 50, 200)};
begin
  if not ${q.allowed("list_samples.tenant", q.read)} then
    ${q.forbidden("not allowed to read samples")}
  end if;
  return coalesce((
    select jsonb_agg(${q.sampleJson("y")} order by y.${s("sequence")} desc)
    from (
      select * from ${samples} x
      where x.${s("tenant")} = list_samples.tenant
        and (not v_filters ? 'status' or x.${s("status")} = v_filters ->> 'status')
      order by x.${s("sequence")} desc
      limit v_limit offset coalesce((v_filters ->> 'offset')::integer, 0)
    ) y
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_samples")}(${idType}, jsonb)`)}

-- Marks testing as done. The sample needs a result and must be in testing.
-- Needs lims.write.
create or replace function ${fn("complete_sample")}(sample_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${samples};
begin
  select * into v_row from ${samples} x where x.${s("id")} = complete_sample.sample_id for update;
  if not found or not ${q.allowed(`v_row.${s("tenant")}`, q.read)} then
    ${q.sampleMissing}
  end if;
  if not ${q.allowed(`v_row.${s("tenant")}`, q.write)} then
    ${q.forbidden("not allowed to complete samples")}
  end if;
  if v_row.${s("status")} <> 'in_testing' then
    ${q.invalid("only a sample in testing can be completed")}
  end if;
  update ${samples} x set ${s("status")} = 'completed', ${s("completedAt")} = now(), ${s("updatedAt")} = now()
  where x.${s("id")} = v_row.${s("id")} returning * into v_row;
  ${q.recordSample("lims_sample.completed", "v_row", "sample testing completed")}
  return ${q.sampleJson("v_row")};
end;
$$;
${userGrant(`${fn("complete_sample")}(uuid)`)}

-- Releases a completed sample. Refused while the latest result of any method is
-- out of specification: record a passing retest first. Needs lims.manage.
create or replace function ${fn("release_sample")}(sample_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${samples};
begin
  select * into v_row from ${samples} x where x.${s("id")} = release_sample.sample_id for update;
  if not found or not ${q.allowed(`v_row.${s("tenant")}`, q.read)} then
    ${q.sampleMissing}
  end if;
  if not ${q.allowed(`v_row.${s("tenant")}`, q.manage)} then
    ${q.forbidden("not allowed to release samples")}
  end if;
  if v_row.${s("status")} <> 'completed' then
    ${q.invalid("only a completed sample can be released")}
  end if;
  if exists (
    select 1 from (
      select distinct on (y.${r("method")}) y.${r("outcome")} as outcome
      from ${results} y where y.${r("sample")} = v_row.${s("id")}
      order by y.${r("method")}, y.${r("testedAt")} desc, y.${r("id")} desc
    ) latest where latest.outcome = 'out_of_spec'
  ) then
    ${q.invalid("a method has an out of specification result; record a passing retest first")}
  end if;
  update ${samples} x set ${s("status")} = 'released', ${s("releasedAt")} = now(), ${s("updatedAt")} = now()
  where x.${s("id")} = v_row.${s("id")} returning * into v_row;
  ${q.recordSample("lims_sample.released", "v_row", "sample released")}
  return ${q.sampleJson("v_row")};
end;
$$;
${userGrant(`${fn("release_sample")}(uuid)`)}

-- Rejects a sample that is not released yet, with a reason of up to 500
-- characters. Needs lims.manage.
create or replace function ${fn("reject_sample")}(sample_id uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${samples};
  v_reason text := trim(reject_sample.reason);
begin
  select * into v_row from ${samples} x where x.${s("id")} = reject_sample.sample_id for update;
  if not found or not ${q.allowed(`v_row.${s("tenant")}`, q.read)} then
    ${q.sampleMissing}
  end if;
  if not ${q.allowed(`v_row.${s("tenant")}`, q.manage)} then
    ${q.forbidden("not allowed to reject samples")}
  end if;
  if v_reason is null or length(v_reason) not between 1 and 500 then
    ${q.invalid("a rejection needs a reason of 1 to 500 characters")}
  end if;
  if v_row.${s("status")} not in ('registered', 'in_testing', 'completed') then
    ${q.invalid("a released or rejected sample cannot be rejected")}
  end if;
  update ${samples} x set ${s("status")} = 'rejected', ${s("rejectionReason")} = v_reason, ${s("updatedAt")} = now()
  where x.${s("id")} = v_row.${s("id")} returning * into v_row;
  ${q.recordSample("lims_sample.rejected", "v_row", "sample rejected")}
  return ${q.sampleJson("v_row")};
end;
$$;
${userGrant(`${fn("reject_sample")}(uuid, text)`)}
`;
}

/**
 * Opens the nonconformity of an out of specification result, when cases is
 * there.
 */
function raiseCase(q: LimsSql): string {
  const cases = q.cases;

  if (cases === undefined) {
    return "";
  }

  const k = (column: string): string => cases.col("kinds", column);
  const c = (column: string): string => cases.col("cases", column);
  const sources = cases.option("sources");

  const source =
    Array.isArray(sources) && sources.includes("lims")
      ? "lims"
      : !Array.isArray(sources) || sources.includes("internal")
        ? "internal"
        : String(sources[0]);

  const kindId = `select y.${k("id")} into v_kind from ${cases.table("kinds")} y
    where y.${k("tenant")}::text = v_sample.${q.s("tenant")}::text and y.${k("key")} = ${sqlString(q.nonconformityKind)} and y.${k("archivedAt")} is null;`;

  return `
    ${kindId}
    if v_kind is null then
      perform ${cases.fn("ensure_case_kinds")}(v_sample.${q.s("tenant")});
      ${kindId}
    end if;
    if v_kind is not null then
      v_case := ${cases.fn("open_case_as")}(v_kind, jsonb_build_object(
        'title', left(v_sample.${q.s("number")} || ': ' || v_method.${q.m("name")} || ' out of specification', 200),
        'description', 'Result ' || v_value::text || coalesce(' ' || v_method.${q.m("unit")}, '') || ' for ' || v_method.${q.m("name")} || ', limits ' || coalesce(v_method.${q.m("lowerLimit")}::text, 'none') || ' to ' || coalesce(v_method.${q.m("upperLimit")}::text, 'none'),
        'source', ${sqlString(source)},
        'occurredAt', v_tested,
        'originType', ${q.subject},
        'originId', v_sample.${q.s("id")}::text
      ), auth.uid());
      update ${q.results} x set ${q.r("case")} = v_case.${c("id")} where x.${q.r("id")} = v_row.${q.r("id")} returning * into v_row;
    end if;`;
}

function instrumentCheck(q: LimsSql): string {
  const { assets } = q;

  const exists =
    assets === undefined
      ? q.invalid("instrumentId needs the assets block")
      : `if not exists (
      select 1 from ${assets.table("assets")} y
      where y.${assets.col("assets", "id")} = v_instrument
        and y.${assets.col("assets", "tenant")}::text = v_sample.${q.s("tenant")}::text
    ) then
      ${q.invalid("the instrument is not an asset of this organization")}
    end if;`;

  const qualified =
    q.instrumentQualification === undefined || q.qualifications === undefined
      ? ""
      : `
    if not ${q.qualifications.fn("qualified_holders")}(v_sample.${q.s("tenant")}, ${sqlString(q.instrumentQualification)}, 'asset', v_tested::date) @> to_jsonb(v_instrument::text) then
      ${q.invalid(`the instrument does not hold a valid ${q.instrumentQualification} qualification on the test date`)}
    end if;`;

  const required =
    q.instrumentQualification === undefined
      ? ""
      : `
  if v_instrument is null then
    ${q.invalid("a result needs the instrument that produced it")}
  end if;`;

  return `${required}
  if v_instrument is not null then
    ${exists}${qualified}
  end if;`;
}

function submissionCheck(q: LimsSql): string {
  const { forms } = q;

  if (forms === undefined) {
    return `if v_submission is not null then
    ${q.invalid("submissionId needs the forms block")}
  end if;`;
  }

  return `if v_submission is not null and not exists (
    select 1 from ${forms.table("submissions")} y
    where y.${forms.col("submissions", "id")} = v_submission
      and y.${forms.col("submissions", "tenant")}::text = v_sample.${q.s("tenant")}::text
      and (v_method.${q.m("form")} is null or y.${forms.col("submissions", "form")} = v_method.${q.m("form")})
  ) then
    ${q.invalid("the submission is not a submission of the method's form in this organization")}
  end if;`;
}

function resultFunctions(ctx: BlockSqlContext, q: LimsSql): string {
  const { fn, m, s, r, samples, methods, results } = q;
  const idType = ctx.idType;
  const cases = q.cases;

  const declare =
    cases === undefined
      ? ""
      : `\n  v_kind uuid;\n  v_case ${cases.table("cases")};`;

  return `
-- Records a result of a test method on a sample, as input { value, instrumentId,
-- submissionId, testedAt, note }. The result is checked against the method's
-- limits and an out of specification result raises the nonconformity case
-- (options.nonconformityKind) when the cases block is installed. The first
-- result moves the sample into testing. With options.instrumentQualification
-- the instrument must hold that qualification on the test date. Retests add
-- results; the latest per method counts. Needs lims.write.
create or replace function ${fn("record_lims_result")}(sample_id uuid, method_id uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_sample ${samples};
  v_method ${methods};
  v_row ${results};
  v_input jsonb := coalesce(record_lims_result.input, '{}'::jsonb);
  v_value numeric;
  v_instrument uuid;
  v_submission uuid;
  v_tested timestamptz;
  v_outcome text;${declare}
begin
  select * into v_sample from ${samples} x where x.${s("id")} = record_lims_result.sample_id for update;
  if not found or not ${q.allowed(`v_sample.${s("tenant")}`, q.read)} then
    ${q.sampleMissing}
  end if;
  if not ${q.allowed(`v_sample.${s("tenant")}`, q.write)} then
    ${q.forbidden("not allowed to record results")}
  end if;
  if v_sample.${s("status")} not in ('registered', 'in_testing') then
    ${q.invalid("results can only be recorded while a sample is registered or in testing")}
  end if;
  if jsonb_typeof(v_input) is distinct from 'object' then
    ${q.invalid("input must be an object")}
  end if;
  select * into v_method from ${methods} x
  where x.${m("id")} = record_lims_result.method_id and x.${m("tenant")} = v_sample.${s("tenant")};
  if not found then
    ${q.methodMissing}
  end if;
  if v_method.${m("archivedAt")} is not null then
    ${q.invalid("this method is archived")}
  end if;
  begin
    v_value := (v_input ->> 'value')::numeric;
    v_instrument := (v_input ->> 'instrumentId')::uuid;
    v_submission := (v_input ->> 'submissionId')::uuid;
    v_tested := coalesce((v_input ->> 'testedAt')::timestamptz, now());
  exception when invalid_text_representation or numeric_value_out_of_range or invalid_datetime_format or datetime_field_overflow then
    ${q.invalid("value is a number, instrumentId and submissionId are ids and testedAt is a timestamp")}
  end;
  if v_value is null or v_value = 'NaN'::numeric then
    ${q.invalid("a result needs a value")}
  end if;
  ${instrumentCheck(q)}
  ${submissionCheck(q)}
  ${ctx.hook("before_lims_result_record", [
    ["uuid", "record_lims_result.sample_id"],
    ["uuid", "record_lims_result.method_id"],
    ["jsonb", "record_lims_result.input"],
  ])}
  v_outcome := case
    when (v_method.${m("lowerLimit")} is not null and v_value < v_method.${m("lowerLimit")})
      or (v_method.${m("upperLimit")} is not null and v_value > v_method.${m("upperLimit")}) then 'out_of_spec'
    else 'in_spec'
  end;
  begin
    insert into ${results} (${r("tenant")}, ${r("sample")}, ${r("method")}, ${r("value")}, ${r("outcome")}, ${r("instrument")}, ${r("submission")}, ${r("note")}, ${r("testedBy")}, ${r("testedAt")})
    values (v_sample.${s("tenant")}, v_sample.${s("id")}, v_method.${m("id")}, v_value, v_outcome, v_instrument, v_submission,
      nullif(trim(v_input ->> 'note'), ''), auth.uid(), v_tested)
    returning * into v_row;
  exception when check_violation then
    ${q.invalid("a note is at most 2000 characters")}
  end;
  if v_sample.${s("status")} = 'registered' then
    update ${samples} x set ${s("status")} = 'in_testing', ${s("updatedAt")} = now() where x.${s("id")} = v_sample.${s("id")};
  end if;
  ${q.recordResult("lims_result.recorded", "v_row", "v_sample", "result recorded")}
  if v_outcome = 'out_of_spec' then${raiseCase(q)}
    ${q.recordResult("lims_result.flagged", "v_row", "v_sample", "result out of specification")}
  end if;
  ${ctx.hook("after_lims_result_record", [["uuid", `v_row.${r("id")}`]])}
  return ${q.resultJson("v_row")};
end;
$$;
${userGrant(`${fn("record_lims_result")}(uuid, uuid, jsonb)`)}

-- Whether an instrument (an asset) may be used on a day. Without
-- options.instrumentQualification every instrument may. Returns { instrumentId,
-- required, qualified }.
create or replace function ${fn("instrument_status")}(tenant ${idType}, asset_id uuid, on_date date default current_date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not ${q.allowed("instrument_status.tenant", q.read)} then
    ${q.forbidden("not allowed to read instruments")}
  end if;
  ${
    q.instrumentQualification === undefined || q.qualifications === undefined
      ? `return jsonb_build_object('instrumentId', instrument_status.asset_id, 'required', false, 'qualified', true);`
      : `return jsonb_build_object('instrumentId', instrument_status.asset_id, 'required', true,
    'qualified', ${q.qualifications.fn("qualified_holders")}(instrument_status.tenant, ${sqlString(q.instrumentQualification)}, 'asset', coalesce(instrument_status.on_date, current_date)) @> to_jsonb(instrument_status.asset_id::text));`
  }
end;
$$;
${userGrant(`${fn("instrument_status")}(${idType}, uuid, date)`)}
`;
}

export function limsFunctions(ctx: BlockSqlContext): string {
  const q = limsSql(ctx);

  return `${methodFunctions(ctx, q)}${sampleFunctions(ctx, q)}${resultFunctions(ctx, q)}`;
}
