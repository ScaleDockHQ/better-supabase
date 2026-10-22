import type { BlockSqlContext } from "../context.ts";
import type { Names, PipelineBinding } from "./pipelines-bindings.ts";

import { rankKeys } from "../../core/rank-keys.ts";
import { sqlIdent, sqlString } from "../../core/template.ts";
import { RANK_KEY_PATTERN, rankAfter } from "../rank-sql.ts";
import {
  columnsObject,
  extraFieldsArg,
  fail,
  userGrant,
  writeExtraColumns,
} from "../shared.ts";
import { watchSql } from "../watch-sql.ts";
import { byType, outcomeCase } from "./pipelines-bindings.ts";

/**
 * ` || jsonb_build_object('fields', ...)` for pipeline row `alias`; empty
 * without extra columns.
 */
const pipelineFields = (names: Names, alias: string): string =>
  names.extras.length === 0
    ? ""
    : ` || jsonb_build_object('fields', ${columnsObject(
        alias,
        names.extras.map((extra) => extra.name),
      )})`;

/**
 * The first pipeline of a subject type and scope, created from the binding's
 * stage template the first time a record needs one.
 */
export function defaultPipeline(
  ctx: BlockSqlContext,
  names: Names,
  bindings: readonly PipelineBinding[],
): string {
  const { fn, t, c } = names;
  const p = (column: string): string => c("pipelines", column);
  const s = (column: string): string => c("stages", column);
  const self = fn("default_pipeline");

  const seed = (binding: PipelineBinding): string => {
    const ranks = rankKeys(binding.stages.length);

    const rows = binding.stages
      .map(
        (stage, index) =>
          `(${sqlString(stage.key)}, ${sqlString(stage.name)}, ${sqlString(stage.category)}, ${sqlString(binding.categories[stage.category] ?? "open")}, ${stage.probability === undefined ? "null::smallint" : `${String(stage.probability)}::smallint`}, ${sqlString(ranks[index] ?? "V")})`,
      )
      .join(",\n          ");

    return `      insert into ${t("pipelines")} (${p("tenant")}, ${p("subjectType")}, ${p("scope")}, ${p("key")}, ${p("name")}, ${p("isDefault")})
      values (default_pipeline.tenant, default_pipeline.subject_type, default_pipeline.scope_id, 'default', 'Default', true)
      on conflict do nothing
      returning ${p("id")} into v_id;
      if v_id is null then
        return ${self}(default_pipeline.tenant, default_pipeline.subject_type, default_pipeline.scope_id);
      end if;
      insert into ${t("stages")} (${s("tenant")}, ${s("pipeline")}, ${s("key")}, ${s("systemKey")}, ${s("name")}, ${s("category")}, ${s("outcome")}, ${s("probability")}, ${s("rank")})
      select default_pipeline.tenant, v_id, x.key, x.key, x.name, x.category, x.outcome, x.probability, x.rank
      from (values
          ${rows}
      ) x(key, name, category, outcome, probability, rank);`;
  };

  return `
-- The default pipeline of a subject type in a tenant and scope. The first
-- call creates it from the type's stage template in options.subjects.
create or replace function ${self}(tenant ${ctx.idType}, subject_type text, scope_id text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  select x.${p("id")} into v_id from ${t("pipelines")} x
  where x.${p("tenant")} = default_pipeline.tenant
    and x.${p("subjectType")} = default_pipeline.subject_type
    and x.${p("scope")} is not distinct from default_pipeline.scope_id
    and x.${p("archivedAt")} is null
  order by x.${p("isDefault")} desc, x.${p("rank")} collate "C"
  limit 1;
  if v_id is not null then
    return v_id;
  end if;
  ${byType(
    "default_pipeline.subject_type",
    bindings,
    seed,
    fail(
      "PIPELINE_SUBJECT_UNKNOWN",
      "this subject type has no pipeline binding",
      "22023",
    ),
  )}
  return v_id;
end;
$$;
revoke execute on function ${self}(${ctx.idType}, text, text) from public, anon, authenticated;
grant execute on function ${self}(${ctx.idType}, text, text) to service_role;
`;
}

/**
 * The before trigger on one bound table: checks the stage, stamps entry, writes
 * history.
 */
export function stageTrigger(
  ctx: BlockSqlContext,
  names: Names,
  binding: PipelineBinding,
): string {
  const { fn, t, c } = names;
  const subject = binding.subject;
  const tenantColumn = subject.tenant ?? "";
  const col = (name: string): string => sqlIdent(name);
  const stage = col(binding.stage);
  const pipeline = col(binding.pipeline);
  const tenant = `new.${tenantColumn}`;
  const subjectId = `new.${subject.id}::text`;

  const scope =
    binding.scope === undefined ? "null" : `new.${col(binding.scope)}::text`;

  const h = (column: string): string => c("history", column);

  const amount =
    binding.amount === undefined ? "null" : `new.${col(binding.amount)}`;

  const currency =
    binding.currency === undefined ? "null" : `new.${col(binding.currency)}`;

  const entered =
    binding.enteredAt === undefined
      ? ""
      : `\n    new.${col(binding.enteredAt)} := now();`;

  const name = `bsb_pipeline_${binding.type}`;

  const transitions = ctx.hasTable("transitions")
    ? `
    if tg_op = 'UPDATE' and old.${stage} is not null
      and exists (select 1 from ${t("transitions")} x where x.${c("transitions", "pipeline")} = new.${pipeline})
      and not exists (
        select 1 from ${t("transitions")} x
        where x.${c("transitions", "from")} = old.${stage} and x.${c("transitions", "to")} = new.${stage}
      ) then
      ${fail("PIPELINE_TRANSITION_INVALID", "that stage change is not allowed in this pipeline", "22023")}
    end if;`
    : "";

  const notifications = ctx.installed("notifications")
    ? ctx.of("notifications")
    : undefined;

  const watch =
    binding.owner === undefined
      ? ""
      : watchSql(ctx, {
          tenant,
          user: `new.${col(binding.owner)}`,
          subjectType: sqlString(binding.type),
          subjectId,
        });

  const follow =
    binding.owner === undefined || watch === ""
      ? ""
      : `
  -- The owner watches the record; a level they already chose stays.
  if new.${col(binding.owner)} is not null and (tg_op = 'INSERT' or new.${col(binding.owner)} is distinct from old.${col(binding.owner)}) then
    ${watch}
  end if;`;

  const notify =
    notifications === undefined
      ? ""
      : `
    if tg_op = 'UPDATE' then
      ${ctx.notify(
        `jsonb_build_object(
        'type', 'pipeline.stage_changed',
        'tenant', ${tenant},
        'actor', auth.uid(),
        'subject_type', ${sqlString(binding.type)},
        'subject_id', ${subjectId},
        'summary', v_stage_name,
        'key', 'pipeline.stage_changed:' || ${subjectId} || ':' || new.${stage}::text || ':' || extract(epoch from now())::text,
        'data', jsonb_build_object('pipelineId', new.${pipeline}, 'fromStageId', old.${stage}, 'toStageId', new.${stage}, 'outcome', v_outcome)
      )`,
        { indent: "      " },
      )}
    end if;`;

  const ownerColumns =
    binding.owner === undefined ? "" : `, ${col(binding.owner)}`;

  return `
create or replace function better_supabase.${name}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_category text;
  v_outcome text;
  v_stage_name text;
  v_claims text;
begin
  if tg_op = 'UPDATE' and new.${stage} is not distinct from old.${stage} and new.${pipeline} is not distinct from old.${pipeline} then${follow}
    return new;
  end if;
  if new.${pipeline} is null then
    if new.${stage} is not null then
      select s.${c("stages", "pipeline")} into new.${pipeline} from ${t("stages")} s where s.${c("stages", "id")} = new.${stage};
    else
      new.${pipeline} := ${fn("default_pipeline")}(${tenant}, ${sqlString(binding.type)}, ${scope});
    end if;
  end if;
  if new.${stage} is null then
    select s.${c("stages", "id")} into new.${stage} from ${t("stages")} s
    where s.${c("stages", "pipeline")} = new.${pipeline} and s.${c("stages", "outcome")} = 'open' and s.${c("stages", "archivedAt")} is null
    order by s.${c("stages", "rank")} collate "C"
    limit 1;
  end if;
  select s.${c("stages", "category")}, s.${c("stages", "outcome")}, s.${c("stages", "name")}
    into v_category, v_outcome, v_stage_name
  from ${t("stages")} s
  join ${t("pipelines")} p on p.${c("pipelines", "id")} = s.${c("stages", "pipeline")}
  where s.${c("stages", "id")} = new.${stage}
    and s.${c("stages", "pipeline")} = new.${pipeline}
    and s.${c("stages", "archivedAt")} is null
    and p.${c("pipelines", "archivedAt")} is null
    and p.${c("pipelines", "tenant")}::text = ${tenant}::text
    and p.${c("pipelines", "subjectType")} = ${sqlString(binding.type)}
    and p.${c("pipelines", "scope")} is not distinct from ${scope};
  if not found then
    ${fail("PIPELINE_STAGE_INVALID", "the stage is not an active stage of this record's pipeline", "22023")}
  end if;
  if tg_op = 'INSERT' or new.${stage} is distinct from old.${stage} then${transitions}
    ${ctx.hook("before_pipeline_stage_change", [
      ["text", sqlString(binding.type)],
      ["text", subjectId],
      ["uuid", `case when tg_op = 'UPDATE' then old.${stage} end`],
      ["uuid", `new.${stage}`],
    ])}${entered}
    update ${t("history")} set ${h("exitedAt")} = now()
    where ${h("subjectType")} = ${sqlString(binding.type)} and ${h("subjectId")} = ${subjectId} and ${h("exitedAt")} is null;
    insert into ${t("history")} (${h("tenant")}, ${h("subjectType")}, ${h("subjectId")}, ${h("pipeline")}, ${h("fromStage")}, ${h("toStage")}, ${h("stageName")}, ${h("category")}, ${h("outcome")}, ${h("amount")}, ${h("currency")}, ${h("actor")})
    values (${tenant}, ${sqlString(binding.type)}, ${subjectId}, new.${pipeline}, case when tg_op = 'UPDATE' then old.${stage} end, new.${stage}, v_stage_name, v_category, v_outcome, ${amount}, ${currency}, auth.uid());
    if tg_op = 'UPDATE' then
      ${ctx.record({
        type: "pipeline.stage_changed",
        payload: `jsonb_build_object('organizationId', ${tenant}::text, 'subjectType', ${sqlString(binding.type)}, 'subjectId', ${subjectId}, 'pipelineId', new.${pipeline}, 'fromStageId', old.${stage}, 'toStageId', new.${stage}, 'category', v_category, 'outcome', v_outcome)`,
        subject: `'pipelines/' || new.${pipeline}::text`,
        tenant: `${tenant}::text`,
        audit: false,
      })}
    end if;${notify}
    ${ctx.hook("after_pipeline_stage_change", [
      ["text", sqlString(binding.type)],
      ["text", subjectId],
      ["uuid", `new.${stage}`],
    ])}
  end if;${follow}
  return new;
end;
$$;
drop trigger if exists ${name} on ${subject.qualified};
create trigger ${name} before insert or update of ${stage}, ${pipeline}${ownerColumns} on ${subject.qualified}
for each row execute function better_supabase.${name}();
${statusTrigger(names, binding)}`;
}

/**
 * The after trigger that writes the status a stage category maps to, as a
 * separate update so a state-machine trigger on the status column runs.
 */
function statusTrigger(names: Names, binding: PipelineBinding): string {
  const name = `bsb_pipeline_status_${binding.type}`;
  const subject = binding.subject;

  if (binding.status === undefined) {
    return `drop trigger if exists ${name} on ${subject.qualified};
drop function if exists better_supabase.${name}();`;
  }

  const { t, c } = names;
  const status = sqlIdent(binding.status.column);
  const stage = sqlIdent(binding.stage);

  const mapping = Object.entries(binding.status.values)
    .map(
      ([category, value]) =>
        `when ${sqlString(category)} then ${sqlString(value)}`,
    )
    .join(" ");

  return `
create or replace function better_supabase.${name}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text;
begin
  select case s.${c("stages", "category")} ${mapping} end into v_status
  from ${t("stages")} s where s.${c("stages", "id")} = new.${stage};
  if v_status is not null and v_status is distinct from new.${status}::text then
    update ${subject.qualified} r set ${status} = (jsonb_populate_record(null::${subject.qualified}, jsonb_build_object(${sqlString(binding.status.column)}, v_status))).${status}
    where r.${subject.id} = new.${subject.id};
  end if;
  return null;
end;
$$;
drop trigger if exists ${name} on ${subject.qualified};
create trigger ${name} after insert or update of ${stage} on ${subject.qualified}
for each row execute function better_supabase.${name}();`;
}

export function manageFunctions(
  ctx: BlockSqlContext,
  names: Names,
  bindings: readonly PipelineBinding[],
): string {
  const { fn, t, c } = names;
  const p = (column: string): string => c("pipelines", column);
  const s = (column: string): string => c("stages", column);

  const guard = (
    tenant: string,
  ): string => `if not (auth.role() = 'service_role' or ${ctx.scope.can(tenant, names.manage)}) then
    ${fail("PIPELINE_FORBIDDEN", "not allowed to manage pipelines")}
  end if;`;

  const categoryCheck = byType(
    "v_subject_type",
    bindings,
    (binding) =>
      `      v_outcome := ${outcomeCase(binding, "save_pipeline_stage.category")};`,
    fail(
      "PIPELINE_SUBJECT_UNKNOWN",
      "this subject type has no pipeline binding",
      "22023",
    ),
  );

  const occupied = (
    pipelineFilter: (binding: PipelineBinding) => string,
  ): string =>
    byType(
      "v_subject_type",
      bindings,
      (
        binding,
      ) => `      perform 1 from ${binding.subject.qualified} r where ${pipelineFilter(binding)} limit 1;
      v_used := found;`,
      "v_used := false;",
    );

  const transitions = ctx.hasTable("transitions")
    ? `
-- Replaces the allowed stage changes of a pipeline. An empty list allows
-- every change; pairs is a list of { "from": stage id, "to": stage id }.
create or replace function ${fn("set_pipeline_transitions")}(pipeline uuid, pairs jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_count integer;
begin
  select x.${p("tenant")} into v_tenant from ${t("pipelines")} x where x.${p("id")} = set_pipeline_transitions.pipeline;
  if v_tenant is null then
    ${fail("PIPELINE_NOT_FOUND", "pipeline not found", "P0002")}
  end if;
  ${guard("v_tenant")}
  if jsonb_typeof(coalesce(set_pipeline_transitions.pairs, '[]')) <> 'array' then
    ${fail("PIPELINE_TRANSITIONS_INVALID", "pairs must be a list of { from, to } stage ids", "22023")}
  end if;
  delete from ${t("transitions")} x where x.${c("transitions", "pipeline")} = set_pipeline_transitions.pipeline;
  insert into ${t("transitions")} (${c("transitions", "tenant")}, ${c("transitions", "pipeline")}, ${c("transitions", "from")}, ${c("transitions", "to")})
  select v_tenant, set_pipeline_transitions.pipeline, (pair ->> 'from')::uuid, (pair ->> 'to')::uuid
  from jsonb_array_elements(coalesce(set_pipeline_transitions.pairs, '[]')) pair
  on conflict do nothing;
  get diagnostics v_count = row_count;
  if exists (
    select 1 from ${t("transitions")} x
    left join ${t("stages")} a on a.${s("id")} = x.${c("transitions", "from")} and a.${s("pipeline")} = x.${c("transitions", "pipeline")}
    left join ${t("stages")} b on b.${s("id")} = x.${c("transitions", "to")} and b.${s("pipeline")} = x.${c("transitions", "pipeline")}
    where x.${c("transitions", "pipeline")} = set_pipeline_transitions.pipeline and (a.${s("id")} is null or b.${s("id")} is null)
  ) then
    ${fail("PIPELINE_TRANSITIONS_INVALID", "every stage must belong to the pipeline", "22023")}
  end if;
  return v_count;
end;
$$;
${userGrant(`${fn("set_pipeline_transitions")}(uuid, jsonb)`)}
`
    : "";

  const configured = (
    type: string,
    payload: string,
    subject: string,
    tenant: string,
    summary: string,
  ): string =>
    ctx.record({
      type,
      payload,
      subject,
      tenant,
      audit: {
        category: "configuration",
        targetType: "pipeline",
        recordId: "v_pipeline::text",
        summary,
      },
    });

  return `
-- Creates a pipeline (pipeline null) or renames one. The first pipeline of a
-- subject type and scope is its default. Returns its row.
${extraFieldsArg(names.extras).drop(fn("save_pipeline"), `${ctx.idType}, uuid, text, text, text, text, boolean`)}
create or replace function ${fn("save_pipeline")}(tenant ${ctx.idType}, pipeline uuid, subject_type text, key text, name text, scope_id text, is_default boolean${extraFieldsArg(names.extras).param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pipeline uuid := save_pipeline.pipeline;
  v_created boolean := save_pipeline.pipeline is null;
begin
  ${guard("save_pipeline.tenant")}
  if not (save_pipeline.subject_type = any (${sqlString(`{${bindings.map((binding) => binding.type).join(",")}}`)}::text[])) then
    ${fail("PIPELINE_SUBJECT_UNKNOWN", "this subject type has no pipeline binding", "22023")}
  end if;
  ${ctx.hook("before_pipeline_save", [
    [ctx.idType, "save_pipeline.tenant"],
    ["uuid", "save_pipeline.pipeline"],
    ["text", "save_pipeline.subject_type"],
    ["text", "save_pipeline.key"],
  ])}
  if coalesce(save_pipeline.is_default, false) then
    update ${t("pipelines")} x set ${p("isDefault")} = false
    where x.${p("tenant")} = save_pipeline.tenant and x.${p("subjectType")} = save_pipeline.subject_type
      and x.${p("scope")} is not distinct from save_pipeline.scope_id and x.${p("isDefault")}
      and x.${p("id")} is distinct from save_pipeline.pipeline;
  end if;
  begin
    if v_created then
      insert into ${t("pipelines")} (${p("tenant")}, ${p("subjectType")}, ${p("scope")}, ${p("key")}, ${p("name")}, ${p("isDefault")}, ${p("rank")})
      values (save_pipeline.tenant, save_pipeline.subject_type, save_pipeline.scope_id, save_pipeline.key, save_pipeline.name,
        coalesce(save_pipeline.is_default, false) or not exists (
          select 1 from ${t("pipelines")} x where x.${p("tenant")} = save_pipeline.tenant and x.${p("subjectType")} = save_pipeline.subject_type
            and x.${p("scope")} is not distinct from save_pipeline.scope_id and x.${p("archivedAt")} is null),
        ${rankAfter(`(select max(x.${p("rank")} collate "C") from ${t("pipelines")} x where x.${p("tenant")} = save_pipeline.tenant and x.${p("subjectType")} = save_pipeline.subject_type)`)})
      returning ${p("id")} into v_pipeline;
    else
      update ${t("pipelines")} x set ${p("key")} = save_pipeline.key, ${p("name")} = save_pipeline.name,
        ${p("isDefault")} = coalesce(save_pipeline.is_default, x.${p("isDefault")}), ${p("updatedAt")} = now()
      where x.${p("id")} = save_pipeline.pipeline and x.${p("tenant")} = save_pipeline.tenant
        and x.${p("subjectType")} = save_pipeline.subject_type;
      if not found then
        ${fail("PIPELINE_NOT_FOUND", "pipeline not found", "P0002")}
      end if;
    end if;
  exception when unique_violation then
    ${fail("PIPELINE_KEY_TAKEN", "another pipeline of this type has this key", "23505")}
  end;${writeExtraColumns(t("pipelines"), names.extras, "save_pipeline.fields", `x.${p("id")} = v_pipeline`)}
  if v_created then
    ${configured("pipeline.created", "jsonb_build_object('organizationId', save_pipeline.tenant, 'pipelineId', v_pipeline, 'subjectType', save_pipeline.subject_type, 'key', save_pipeline.key)", "'pipelines/' || v_pipeline::text", "save_pipeline.tenant::text", "'created pipeline ' || save_pipeline.name")}
  else
    ${configured("pipeline.updated", "jsonb_build_object('organizationId', save_pipeline.tenant, 'pipelineId', v_pipeline, 'subjectType', save_pipeline.subject_type, 'key', save_pipeline.key)", "'pipelines/' || v_pipeline::text", "save_pipeline.tenant::text", "'updated pipeline ' || save_pipeline.name")}
  end if;
  ${ctx.hook("after_pipeline_save", [
    ["uuid", "v_pipeline"],
    ["boolean", "v_created"],
  ])}
  return (select to_jsonb(x)${pipelineFields(names, "x")} from ${t("pipelines")} x where x.${p("id")} = v_pipeline);
end;
$$;
${userGrant(`${fn("save_pipeline")}(${ctx.idType}, uuid, text, text, text, text, boolean${extraFieldsArg(names.extras).type})`)}

-- Archives a pipeline. Records still in it must move to another first.
create or replace function ${fn("archive_pipeline")}(pipeline uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_subject_type text;
  v_used boolean;
  v_pipeline uuid := archive_pipeline.pipeline;
begin
  select x.${p("tenant")}, x.${p("subjectType")} into v_tenant, v_subject_type
  from ${t("pipelines")} x where x.${p("id")} = archive_pipeline.pipeline and x.${p("archivedAt")} is null;
  if v_tenant is null then
    return false;
  end if;
  ${guard("v_tenant")}
  ${occupied((binding) => `r.${sqlIdent(binding.pipeline)} = archive_pipeline.pipeline`)}
  if v_used then
    ${fail("PIPELINE_IN_USE", "records are still in this pipeline; move them first", "23503")}
  end if;
  update ${t("pipelines")} x set ${p("archivedAt")} = now(), ${p("isDefault")} = false, ${p("updatedAt")} = now()
  where x.${p("id")} = archive_pipeline.pipeline;
  ${configured("pipeline.archived", "jsonb_build_object('organizationId', v_tenant, 'pipelineId', v_pipeline, 'subjectType', v_subject_type)", "'pipelines/' || v_pipeline::text", "v_tenant::text", "'archived a pipeline'")}
  return true;
end;
$$;
${userGrant(`${fn("archive_pipeline")}(uuid)`)}

-- Creates a stage at the end of a pipeline (stage null) or changes one.
-- The category must be one the subject type declares; it sets the outcome.
create or replace function ${fn("save_pipeline_stage")}(pipeline uuid, stage uuid, key text, name text, category text, probability integer, rotting_after_days integer, wip_limit integer, color text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_subject_type text;
  v_outcome text;
  v_stage uuid := save_pipeline_stage.stage;
  v_pipeline uuid := save_pipeline_stage.pipeline;
  v_used boolean;
begin
  select x.${p("tenant")}, x.${p("subjectType")} into v_tenant, v_subject_type
  from ${t("pipelines")} x where x.${p("id")} = save_pipeline_stage.pipeline and x.${p("archivedAt")} is null;
  if v_tenant is null then
    ${fail("PIPELINE_NOT_FOUND", "pipeline not found", "P0002")}
  end if;
  ${guard("v_tenant")}
  ${categoryCheck}
  if v_outcome is null then
    ${fail("PIPELINE_CATEGORY_UNKNOWN", "this subject type has no such category", "22023")}
  end if;
  ${ctx.hook("before_pipeline_stage_save", [
    ["uuid", "save_pipeline_stage.pipeline"],
    ["uuid", "save_pipeline_stage.stage"],
    ["text", "save_pipeline_stage.key"],
    ["text", "save_pipeline_stage.category"],
  ])}
  begin
    if v_stage is null then
      insert into ${t("stages")} (${s("tenant")}, ${s("pipeline")}, ${s("key")}, ${s("name")}, ${s("category")}, ${s("outcome")}, ${s("probability")}, ${s("rottingAfterDays")}, ${s("wipLimit")}, ${s("color")}, ${s("rank")})
      values (v_tenant, save_pipeline_stage.pipeline, save_pipeline_stage.key, save_pipeline_stage.name, save_pipeline_stage.category, v_outcome,
        save_pipeline_stage.probability, save_pipeline_stage.rotting_after_days, save_pipeline_stage.wip_limit, save_pipeline_stage.color,
        ${rankAfter(`(select max(x.${s("rank")} collate "C") from ${t("stages")} x where x.${s("pipeline")} = save_pipeline_stage.pipeline)`)})
      returning ${s("id")} into v_stage;
    else
      -- A stage holding records keeps its outcome, so won stays won.
      if exists (select 1 from ${t("stages")} x where x.${s("id")} = v_stage and x.${s("outcome")} <> v_outcome) then
        ${occupied((binding) => `r.${sqlIdent(binding.stage)} = v_stage`)}
        if v_used then
          ${fail("PIPELINE_STAGE_IN_USE", "records are in this stage; its outcome can't change", "23503")}
        end if;
      end if;
      update ${t("stages")} x set ${s("key")} = save_pipeline_stage.key, ${s("name")} = save_pipeline_stage.name,
        ${s("category")} = save_pipeline_stage.category, ${s("outcome")} = v_outcome,
        ${s("probability")} = save_pipeline_stage.probability, ${s("rottingAfterDays")} = save_pipeline_stage.rotting_after_days,
        ${s("wipLimit")} = save_pipeline_stage.wip_limit, ${s("color")} = save_pipeline_stage.color, ${s("updatedAt")} = now()
      where x.${s("id")} = v_stage and x.${s("pipeline")} = save_pipeline_stage.pipeline;
      if not found then
        ${fail("PIPELINE_STAGE_NOT_FOUND", "stage not found", "P0002")}
      end if;
    end if;
  exception when unique_violation then
    ${fail("PIPELINE_STAGE_KEY_TAKEN", "another stage of this pipeline has this key", "23505")}
  end;
  ${configured("pipeline_stage.saved", "jsonb_build_object('organizationId', v_tenant, 'pipelineId', v_pipeline, 'stageId', v_stage, 'key', save_pipeline_stage.key, 'category', save_pipeline_stage.category)", "'pipelines/' || v_pipeline::text", "v_tenant::text", "'saved stage ' || save_pipeline_stage.name")}
  ${ctx.hook("after_pipeline_stage_save", [["uuid", "v_stage"]])}
  return (select to_jsonb(x) from ${t("stages")} x where x.${s("id")} = v_stage);
end;
$$;
${userGrant(`${fn("save_pipeline_stage")}(uuid, uuid, text, text, text, integer, integer, integer, text)`)}

-- Moves a stage to a rank key the client computed with rankBetween.
create or replace function ${fn("rank_pipeline_stage")}(stage uuid, rank text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  select x.${s("tenant")} into v_tenant from ${t("stages")} x where x.${s("id")} = rank_pipeline_stage.stage;
  if v_tenant is null then
    return false;
  end if;
  ${guard("v_tenant")}
  if rank_pipeline_stage.rank is null or rank_pipeline_stage.rank !~ ${RANK_KEY_PATTERN} then
    ${fail("PIPELINE_RANK_INVALID", "not a rank key", "22023")}
  end if;
  update ${t("stages")} x set ${s("rank")} = rank_pipeline_stage.rank, ${s("updatedAt")} = now()
  where x.${s("id")} = rank_pipeline_stage.stage;
  return true;
end;
$$;
${userGrant(`${fn("rank_pipeline_stage")}(uuid, text)`)}

-- Archives an empty stage. The last open stage of a pipeline stays.
create or replace function ${fn("archive_pipeline_stage")}(stage uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_pipeline uuid;
  v_subject_type text;
  v_outcome text;
  v_used boolean;
  v_stage uuid := archive_pipeline_stage.stage;
begin
  select x.${s("tenant")}, x.${s("pipeline")}, x.${s("outcome")}, y.${p("subjectType")}
    into v_tenant, v_pipeline, v_outcome, v_subject_type
  from ${t("stages")} x join ${t("pipelines")} y on y.${p("id")} = x.${s("pipeline")}
  where x.${s("id")} = archive_pipeline_stage.stage and x.${s("archivedAt")} is null;
  if v_tenant is null then
    return false;
  end if;
  ${guard("v_tenant")}
  ${occupied((binding) => `r.${sqlIdent(binding.stage)} = archive_pipeline_stage.stage`)}
  if v_used then
    ${fail("PIPELINE_STAGE_IN_USE", "records are in this stage; move them first", "23503")}
  end if;
  if v_outcome = 'open' and not exists (
    select 1 from ${t("stages")} x where x.${s("pipeline")} = v_pipeline and x.${s("outcome")} = 'open'
      and x.${s("archivedAt")} is null and x.${s("id")} <> archive_pipeline_stage.stage
  ) then
    ${fail("PIPELINE_LAST_OPEN_STAGE", "a pipeline keeps at least one open stage", "23514")}
  end if;
  update ${t("stages")} x set ${s("archivedAt")} = now(), ${s("updatedAt")} = now() where x.${s("id")} = archive_pipeline_stage.stage;
  ${ctx.record({
    type: "pipeline_stage.archived",
    payload:
      "jsonb_build_object('organizationId', v_tenant, 'pipelineId', v_pipeline, 'stageId', v_stage)",
    subject: "'pipelines/' || v_pipeline::text",
    tenant: "v_tenant::text",
    audit: {
      category: "configuration",
      targetType: "pipeline_stage",
      recordId: "v_stage::text",
      summary: "'archived a pipeline stage'",
    },
  })}
  return true;
end;
$$;
${userGrant(`${fn("archive_pipeline_stage")}(uuid)`)}
${transitions}`;
}

export function readFunctions(
  idType: string,
  names: Names,
  bindings: readonly PipelineBinding[],
): string {
  const { fn, t, c } = names;
  const s = (column: string): string => c("stages", column);
  const h = (column: string): string => c("history", column);

  const board = byType(
    "pipeline_board.subject_type",
    bindings,
    (binding) => {
      const r = (column: string): string => `r.${sqlIdent(column)}`;
      const deleted = binding.subject.config.deletedAt;
      const live = deleted === undefined ? "" : ` and ${r(deleted)} is null`;

      const owner =
        binding.owner === undefined
          ? ""
          : ` and (pipeline_board.owner is null or ${r(binding.owner)} = pipeline_board.owner)`;

      const money =
        binding.amount === undefined || binding.currency === undefined
          ? "null::text as currency, null::bigint as amount, null::numeric as weighted"
          : `${r(binding.currency)}::text as currency, ${r(binding.amount)}::bigint as amount,
            ${r(binding.amount)} * coalesce(${binding.probability === undefined ? "null" : r(binding.probability)}, st.${s("probability")}, 0) / 100.0 as weighted`;

      return `      return (
        with rows as (
          select ${r(binding.stage)} as stage_id, ${money}
          from ${binding.subject.qualified} r
          join ${t("stages")} st on st.${s("id")} = ${r(binding.stage)}
          where ${r(binding.pipeline)} = pipeline_board.pipeline${live}${owner}
        ),
        counts as (select stage_id, count(*) as n from rows group by stage_id),
        sums as (
          select stage_id, jsonb_agg(jsonb_build_object('currency', currency, 'amount', amount::text, 'weighted', round(weighted)::bigint::text) order by currency) as totals
          from (select stage_id, currency, coalesce(sum(amount), 0) as amount, coalesce(sum(weighted), 0) as weighted from rows where currency is not null group by stage_id, currency) x
          group by stage_id
        )
        select coalesce(jsonb_agg(jsonb_build_object(
          'stageId', st.${s("id")}, 'key', st.${s("key")}, 'name', st.${s("name")}, 'color', st.${s("color")},
          'category', st.${s("category")}, 'outcome', st.${s("outcome")}, 'probability', st.${s("probability")},
          'wipLimit', st.${s("wipLimit")}, 'count', coalesce(n.n, 0),
          'overLimit', st.${s("wipLimit")} is not null and coalesce(n.n, 0) > st.${s("wipLimit")},
          'totals', coalesce(m.totals, '[]'::jsonb)
        ) order by st.${s("rank")} collate "C"), '[]'::jsonb)
        from ${t("stages")} st
        left join counts n on n.stage_id = st.${s("id")}
        left join sums m on m.stage_id = st.${s("id")}
        where st.${s("pipeline")} = pipeline_board.pipeline and st.${s("archivedAt")} is null
      );`;
    },
    fail(
      "PIPELINE_SUBJECT_UNKNOWN",
      "this subject type has no pipeline binding",
      "22023",
    ),
  );

  return `
-- One entry per active stage, in board order: the count of records the
-- caller can see, and per currency the amount and the amount weighted by
-- probability. Amounts are text so bigint minor units survive JSON.
create or replace function ${fn("pipeline_board")}(subject_type text, pipeline uuid, owner uuid default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  ${board}
end;
$$;
${userGrant(`${fn("pipeline_board")}(text, uuid, uuid)`)}

-- Per stage, between since and until: how many records entered it, how long
-- the ones that left stayed on average, and the share that went on to a
-- success stage. Reads the history the caller can see.
create or replace function ${fn("pipeline_stats")}(pipeline uuid, since timestamptz, until timestamptz)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with window_rows as (
    select * from ${t("history")} h
    where h.${h("pipeline")} = pipeline_stats.pipeline
      and h.${h("enteredAt")} >= pipeline_stats.since and h.${h("enteredAt")} < pipeline_stats.until
  ),
  per_stage as (
    select w.${h("toStage")} as stage_id, count(*) as entered,
      avg(extract(epoch from (w.${h("exitedAt")} - w.${h("enteredAt")}))) filter (where w.${h("exitedAt")} is not null) as avg_seconds
    from window_rows w group by w.${h("toStage")}
  ),
  closed as (
    select count(*) filter (where w.${h("outcome")} = 'success') as won,
      count(*) filter (where w.${h("outcome")} = 'failure') as lost
    from window_rows w
  )
  select jsonb_build_object(
    'won', closed.won,
    'lost', closed.lost,
    'winRate', case when closed.won + closed.lost = 0 then null else round(closed.won::numeric / (closed.won + closed.lost), 4) end,
    'stages', coalesce((
      select jsonb_agg(jsonb_build_object('stageId', st.${s("id")}, 'key', st.${s("key")}, 'entered', coalesce(ps.entered, 0), 'averageSeconds', round(ps.avg_seconds)) order by st.${s("rank")} collate "C")
      from ${t("stages")} st left join per_stage ps on ps.stage_id = st.${s("id")}
      where st.${s("pipeline")} = pipeline_stats.pipeline
    ), '[]'::jsonb)
  )
  from closed;
$$;
${userGrant(`${fn("pipeline_stats")}(uuid, timestamptz, timestamptz)`)}

-- The open records of a pipeline the caller can see, oldest entry first:
-- when each entered its stage and whether it sits longer than the stage's
-- rotting limit.
create or replace function ${fn("pipeline_health")}(pipeline uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'subjectType', h.${h("subjectType")}, 'subjectId', h.${h("subjectId")}, 'stageId', h.${h("toStage")},
    'enteredAt', h.${h("enteredAt")},
    'daysInStage', (extract(epoch from now() - h.${h("enteredAt")}) / 86400)::integer,
    'rotting', st.${s("rottingAfterDays")} is not null and now() - h.${h("enteredAt")} > make_interval(days => st.${s("rottingAfterDays")})
  ) order by h.${h("enteredAt")}), '[]'::jsonb)
  from ${t("history")} h
  join ${t("stages")} st on st.${s("id")} = h.${h("toStage")}
  where h.${h("pipeline")} = pipeline_health.pipeline and h.${h("exitedAt")} is null and h.${h("outcome")} = 'open';
$$;
${userGrant(`${fn("pipeline_health")}(uuid)`)}

-- The tenant's active pipelines of a subject type, each with its active
-- stages in board order.
create or replace function ${fn("list_pipelines")}(tenant ${idType}, subject_type text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x)${pipelineFields(names, "x")} || jsonb_build_object('stages', coalesce((
      select jsonb_agg(to_jsonb(st) order by st.${s("rank")} collate "C")
      from ${t("stages")} st where st.${s("pipeline")} = x.${c("pipelines", "id")} and st.${s("archivedAt")} is null
    ), '[]'::jsonb)) order by x.${c("pipelines", "rank")} collate "C"), '[]'::jsonb)
  from ${t("pipelines")} x
  where x.${c("pipelines", "tenant")} = list_pipelines.tenant
    and x.${c("pipelines", "subjectType")} = list_pipelines.subject_type
    and x.${c("pipelines", "archivedAt")} is null;
$$;
${userGrant(`${fn("list_pipelines")}(${idType}, text)`)}
`;
}
