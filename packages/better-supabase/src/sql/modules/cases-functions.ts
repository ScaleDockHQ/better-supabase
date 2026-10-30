import type { BlockSqlContext } from "../context.ts";
import type { CasesSql } from "./cases-sql.ts";

import { sqlString } from "../../core/template.ts";
import { assignNumberSql } from "../numbering-sql.ts";
import { RANK_KEY_PATTERN, rankAfter } from "../rank-sql.ts";
import { fail, serviceGrant, userGrant, writeExtraColumns } from "../shared.ts";
import { CASE_ACTION_TYPES, casesSql } from "./cases-sql.ts";
import { createdFromLink } from "./quotes-functions.ts";

const UPDATE_KEYS = [
  "title",
  "description",
  "severity",
  "source",
  "ownerId",
  "occurredAt",
  "dueOn",
  "reporterContact",
  "fields",
  "stageId",
  "rank",
]
  .map((key) => `'${key}'`)
  .join(", ");

const bool = (value: boolean | undefined, fallback: boolean): string =>
  String(value ?? fallback);

function kindFunctions(ctx: BlockSqlContext, q: CasesSql): string {
  const { fn, k, kinds, kindJson } = q;
  const idType = ctx.idType;
  const defaultPipeline = q.pipelines.fn("default_pipeline");

  const seeded = q.seeded
    .map(
      (kind) =>
        `(${sqlString(kind.key)}, ${sqlString(kind.name)}, ${sqlString(kind.prefix)}, ${kind.effectivenessAfterDays === undefined ? "null::integer" : String(kind.effectivenessAfterDays)}, ${bool(kind.requiresRootCause, true)}, ${bool(kind.requiresActions, true)}, ${bool(kind.requiresEffectiveness, false)}, ${bool(kind.requiresRevisions, false)})`,
    )
    .join(",\n      ");

  const signature = `${idType}, text, text, text, uuid, uuid, integer, boolean, boolean, boolean, boolean, uuid`;

  return `
-- Seeds options.kinds for an organization the first time and gives every kind
-- its pipeline. The other functions call it; it is not an entry point.
create or replace function ${fn("ensure_case_kinds")}(tenant ${idType})
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_kind record;
begin
  if not exists (select 1 from ${kinds} x where x.${k("tenant")} = ensure_case_kinds.tenant) then
    insert into ${kinds} (${k("tenant")}, ${k("key")}, ${k("name")}, ${k("prefix")}, ${k("effectivenessAfterDays")}, ${k("requiresRootCause")}, ${k("requiresActions")}, ${k("requiresEffectiveness")}, ${k("requiresRevisions")})
    select ensure_case_kinds.tenant, s.key, s.name, s.prefix, s.days, s.root_cause, s.actions, s.effectiveness, s.revisions
    from (values
      ${seeded}
    ) s(key, name, prefix, days, root_cause, actions, effectiveness, revisions)
    on conflict do nothing;
  end if;
  for v_kind in
    select x.${k("id")} as id from ${kinds} x
    where x.${k("tenant")} = ensure_case_kinds.tenant and x.${k("pipeline")} is null
    for update skip locked
  loop
    update ${kinds} x set ${k("pipeline")} = ${defaultPipeline}(ensure_case_kinds.tenant, ${q.subject}, v_kind.id::text)
    where x.${k("id")} = v_kind.id;
  end loop;
end;
$$;
${serviceGrant(`${fn("ensure_case_kinds")}(${idType})`)}

-- Creates a kind or, with kind_id, changes one. The prefix starts the numbers
-- of the kind's new cases; the flags set what case_close_blockers checks.
create or replace function ${fn("save_case_kind")}(tenant ${idType}, key text, name text, prefix text, investigation_form_id uuid default null, effectiveness_form_id uuid default null, effectiveness_after_days integer default null, requires_root_cause boolean default true, requires_actions boolean default true, requires_effectiveness boolean default false, requires_revisions boolean default false, kind_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${kinds};
begin
  if not ${q.allowed("save_case_kind.tenant", q.manage)} then
    ${q.forbidden("not allowed to manage case kinds")}
  end if;
  if coalesce(save_case_kind.key, '') !~ '^[a-z][a-z0-9_]{0,40}$' then
    ${q.kindInvalid("key must be lowercase letters, digits and underscores")}
  end if;
  if coalesce(length(trim(save_case_kind.name)), 0) not between 1 and 200 then
    ${q.kindInvalid("name must be 1 to 200 characters")}
  end if;
  if coalesce(save_case_kind.prefix, '') !~ '^[A-Z]{1,6}$' then
    ${q.kindInvalid("prefix must be 1 to 6 capital letters")}
  end if;
  if save_case_kind.effectiveness_after_days is not null and save_case_kind.effectiveness_after_days not between 1 and 365 then
    ${q.kindInvalid("effectiveness_after_days is a whole number from 1 to 365")}
  end if;
  perform ${fn("ensure_case_kinds")}(save_case_kind.tenant);
  if save_case_kind.kind_id is null then
    insert into ${kinds} (${k("tenant")}, ${k("key")}, ${k("name")}, ${k("prefix")}, ${k("investigationForm")}, ${k("effectivenessForm")}, ${k("effectivenessAfterDays")}, ${k("requiresRootCause")}, ${k("requiresActions")}, ${k("requiresEffectiveness")}, ${k("requiresRevisions")})
    values (save_case_kind.tenant, save_case_kind.key, trim(save_case_kind.name), save_case_kind.prefix, save_case_kind.investigation_form_id, save_case_kind.effectiveness_form_id, save_case_kind.effectiveness_after_days,
      coalesce(save_case_kind.requires_root_cause, true), coalesce(save_case_kind.requires_actions, true), coalesce(save_case_kind.requires_effectiveness, false), coalesce(save_case_kind.requires_revisions, false))
    returning * into v_row;
    update ${kinds} x set ${k("pipeline")} = ${defaultPipeline}(v_row.${k("tenant")}, ${q.subject}, v_row.${k("id")}::text)
    where x.${k("id")} = v_row.${k("id")}
    returning * into v_row;
    ${q.recordKind("case_kind.created", "v_row", "case kind created")}
  else
    update ${kinds} x set
      ${k("key")} = save_case_kind.key,
      ${k("name")} = trim(save_case_kind.name),
      ${k("prefix")} = save_case_kind.prefix,
      ${k("investigationForm")} = save_case_kind.investigation_form_id,
      ${k("effectivenessForm")} = save_case_kind.effectiveness_form_id,
      ${k("effectivenessAfterDays")} = save_case_kind.effectiveness_after_days,
      ${k("requiresRootCause")} = coalesce(save_case_kind.requires_root_cause, true),
      ${k("requiresActions")} = coalesce(save_case_kind.requires_actions, true),
      ${k("requiresEffectiveness")} = coalesce(save_case_kind.requires_effectiveness, false),
      ${k("requiresRevisions")} = coalesce(save_case_kind.requires_revisions, false),
      ${k("updatedAt")} = now()
    where x.${k("id")} = save_case_kind.kind_id and x.${k("tenant")} = save_case_kind.tenant
    returning * into v_row;
    if not found then
      ${q.kindMissing}
    end if;
    ${q.recordKind("case_kind.updated", "v_row", "case kind updated")}
  end if;
  return ${kindJson("v_row")};
exception when unique_violation then
  ${q.kindInvalid("another kind of this organization has this key")}
end;
$$;
${userGrant(`${fn("save_case_kind")}(${signature})`)}

-- Archives a kind: its cases stay, and no new case opens with it.
create or replace function ${fn("archive_case_kind")}(kind_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${kinds};
begin
  select * into v_row from ${kinds} x where x.${k("id")} = archive_case_kind.kind_id for update;
  if not found then
    ${q.kindMissing}
  end if;
  if not ${q.allowed(`v_row.${k("tenant")}`, q.manage)} then
    ${q.forbidden("not allowed to manage case kinds")}
  end if;
  if v_row.${k("archivedAt")} is null then
    update ${kinds} x set ${k("archivedAt")} = now(), ${k("updatedAt")} = now()
    where x.${k("id")} = v_row.${k("id")}
    returning * into v_row;
    ${q.recordKind("case_kind.archived", "v_row", "case kind archived")}
  end if;
  return ${kindJson("v_row")};
end;
$$;
${userGrant(`${fn("archive_case_kind")}(uuid)`)}

-- The organization's kinds by name, seeding options.kinds the first time.
create or replace function ${fn("list_case_kinds")}(tenant ${idType}, include_archived boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not ${q.allowed("list_case_kinds.tenant", q.read)} then
    ${q.forbidden("not allowed to read cases")}
  end if;
  perform ${fn("ensure_case_kinds")}(list_case_kinds.tenant);
  return coalesce((
    select jsonb_agg(${kindJson("x")} order by x.${k("name")})
    from ${kinds} x
    where x.${k("tenant")} = list_case_kinds.tenant
      and (coalesce(list_case_kinds.include_archived, false) or x.${k("archivedAt")} is null)
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_case_kinds")}(${idType}, boolean)`)}
`;
}

/** The checks a case's text, severity, source and contact go through. */
function caseChecks(q: CasesSql, source: string): string {
  const description = q.has("cases", "description")
    ? `if length(${source} ->> 'description') > 20000 then
    ${q.invalid("description is at most 20000 characters")}
  end if;`
    : `if nullif(trim(${source} ->> 'description'), '') is not null then
    ${q.invalid("the cases table has no description column")}
  end if;`;

  const contact = q.has("cases", "reporterContact")
    ? `if ${source} ? 'reporterContact' and jsonb_typeof(${source} -> 'reporterContact') not in ('object', 'null') then
    ${q.invalid("reporterContact must be an object")}
  end if;`
    : `if jsonb_typeof(${source} -> 'reporterContact') = 'object' then
    ${q.invalid("the cases table has no reporter_contact column")}
  end if;`;

  return `${description}
  ${contact}
  if ${source} ? 'severity' and ${source} ->> 'severity' is not null and not ((${source} ->> 'severity') = any (${q.severities})) then
    ${fail("CASE_SEVERITY_UNKNOWN", "the severity is not one of options.severities", "22023")}
  end if;
  if ${source} ? 'source' and not (coalesce(${source} ->> 'source', '') = any (${q.sources})) then
    ${fail("CASE_SOURCE_UNKNOWN", "the source is not one of options.sources", "22023")}
  end if;
  if ${source} ? 'fields' and jsonb_typeof(${source} -> 'fields') not in ('object', 'null') then
    ${q.invalid("fields must be an object")}
  end if;`;
}

function openFunctions(ctx: BlockSqlContext, q: CasesSql): string {
  const { fn, k, c, kinds, cases, extras, caseJson } = q;
  const idType = ctx.idType;

  const numberAssign = assignNumberSql(
    ctx,
    ctx.resolved.entityNaming.rename("case"),
    `v_kind.${k("tenant")}`,
    { seq: "v_seq", identifier: "v_identifier" },
    { table: cases, seq: c("sequence"), tenant: c("tenant"), prefix: "" },
  );

  const optional = (["description", "reporterContact", "createdBy"] as const)
    .filter((column) => q.has("cases", column))
    .map((column) => ({
      column,
      value: {
        description: "nullif(trim(v_input ->> 'description'), '')",
        reporterContact: "nullif(v_input -> 'reporterContact', 'null'::jsonb)",
        createdBy: "auth.uid()",
      }[column],
    }));

  const origin = createdFromLink(ctx, {
    tenant: `v_row.${c("tenant")}`,
    sourceType: q.subject,
    sourceId: `v_row.${c("id")}::text`,
    originType: "v_input ->> 'originType'",
    originId: "v_input ->> 'originId'",
  });

  const forms =
    ctx.installed("forms") && ctx.of("forms").mode !== "custom"
      ? ctx.of("forms")
      : undefined;

  const fromSubmission =
    forms === undefined
      ? fail(
          "CASE_FORMS_NOT_INSTALLED",
          "install the forms block to open cases from submissions",
          "55000",
        )
      : `select x.${forms.col("submissions", "tenant")}, x.${forms.col("submissions", "respondent")}, coalesce(x.${forms.col("submissions", "answers")}, '{}'::jsonb)
    into v_tenant, v_respondent, v_answers
  from ${forms.table("submissions")} x
  where x.${forms.col("submissions", "id")} = case_from_submission.submission_id;
  if not found then
    ${fail("CASE_INVALID", "no such form submission", "P0002")}
  end if;
  v_key := coalesce(nullif(v_answers ->> 'kind', ''), ${sqlString(q.intakeKind)});
  perform ${fn("ensure_case_kinds")}(v_tenant);
  select * into v_kind from ${kinds} x
  where x.${k("tenant")} = v_tenant and x.${k("key")} = v_key and x.${k("archivedAt")} is null;
  if not found then
    ${q.kindMissing}
  end if;
  v_input := jsonb_strip_nulls(jsonb_build_object(
    'title', coalesce(nullif(trim(v_answers ->> 'title'), ''), v_kind.${k("name")} || ' from a form'),
    'description', nullif(trim(v_answers ->> 'description'), ''),
    'severity', case when (v_answers ->> 'severity') = any (${q.severities}) then v_answers ->> 'severity' end,
    'source', case
      when (v_answers ->> 'source') = any (${q.sources}) then v_answers ->> 'source'
      when v_respondent is null and 'anonymous' = any (${q.sources}) then 'anonymous'
      when 'customer' = any (${q.sources}) then 'customer'
      else (${q.sources})[1]
    end,
    'occurredAt', v_answers ->> 'occurredAt',
    'reporterContact', nullif(jsonb_strip_nulls(jsonb_build_object(
      'name', nullif(trim(v_answers ->> 'name'), ''),
      'email', nullif(trim(v_answers ->> 'email'), ''),
      'phone', nullif(trim(v_answers ->> 'phone'), '')
    )), '{}'::jsonb)
  ))${q.has("cases", "reporterContact") ? "" : " - 'reporterContact'"};
  v_row := ${fn("open_case_as")}(v_kind.${k("id")}, v_input, v_respondent);
  return jsonb_build_object('subjectType', ${q.subject}, 'subjectId', v_row.${c("id")}::text);`;

  return `
-- Opens a case of kind_id without a permission check, for open_case, form
-- intake and other blocks (medications). input is { title, description,
-- severity, source, occurredAt, ownerId, dueOn, reporterContact, fields,
-- originType, originId }; reporter is who reported it, if anyone signed in.
create or replace function ${fn("open_case_as")}(kind_id uuid, input jsonb, reporter uuid default null)
returns ${cases}
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_kind ${kinds};
  v_row ${cases};
  v_input jsonb := coalesce(open_case_as.input, '{}'::jsonb);
  v_title text := trim(v_input ->> 'title');
  v_seq bigint;
  v_identifier text;
  v_last text;
  v_rank text;
begin
  select * into v_kind from ${kinds} x where x.${k("id")} = open_case_as.kind_id;
  if not found then
    ${q.kindMissing}
  end if;
  if v_kind.${k("archivedAt")} is not null then
    ${q.kindArchived}
  end if;
  if jsonb_typeof(v_input) is distinct from 'object' then
    ${q.invalid("input must be an object")}
  end if;
  if coalesce(length(v_title), 0) not between 1 and 200 then
    ${q.invalid("a case needs a title of 1 to 200 characters")}
  end if;
  ${caseChecks(q, "v_input")}
  ${ctx.hook("before_case_open", [
    [idType, `v_kind.${k("tenant")}`],
    ["jsonb", `v_input || jsonb_build_object('kind', v_kind.${k("key")})`],
  ])}
  if v_kind.${k("pipeline")} is null then
    perform ${fn("ensure_case_kinds")}(v_kind.${k("tenant")});
    select * into v_kind from ${kinds} x where x.${k("id")} = open_case_as.kind_id;
  end if;
  ${numberAssign}
  select max(x.${c("rank")}) into v_last from ${cases} x
  where x.${c("tenant")} = v_kind.${k("tenant")} and x.${c("pipeline")} = v_kind.${k("pipeline")};
  v_rank := ${rankAfter("v_last")};
  insert into ${cases} (${c("tenant")}, ${c("kind")}, ${c("number")}, ${c("sequence")}, ${c("title")}, ${c("severity")}, ${c("source")}, ${c("reporter")}, ${c("owner")}, ${c("occurredAt")}, ${c("dueOn")}, ${c("pipeline")}, ${c("rank")}${optional.map(({ column }) => `, ${c(column)}`).join("")})
  values (v_kind.${k("tenant")}, v_kind.${k("id")}, v_kind.${k("prefix")} || '-' || v_identifier, v_seq, v_title,
    v_input ->> 'severity', coalesce(v_input ->> 'source', 'internal'), open_case_as.reporter,
    nullif(v_input ->> 'ownerId', '')::uuid, nullif(v_input ->> 'occurredAt', '')::timestamptz, nullif(v_input ->> 'dueOn', '')::date,
    v_kind.${k("pipeline")}, v_rank${optional.map(({ value }) => `, ${value}`).join("")})
  returning * into v_row;${writeExtraColumns(cases, extras, "coalesce(v_input -> 'fields', '{}'::jsonb)", `x.${c("id")} = v_row.${c("id")}`, "v_row")}
  if v_input ->> 'originType' is not null and v_input ->> 'originId' is not null then
    ${origin === "" ? "null;" : origin}
  end if;
  ${q.record("case.created", "v_row", `v_kind.${k("key")}`, "case opened")}
  ${ctx.hook("after_case_open", [["uuid", `v_row.${c("id")}`]])}
  return v_row;
end;
$$;
${serviceGrant(`${fn("open_case_as")}(uuid, jsonb, uuid)`)}

-- Opens a case of the kind with key kind, with fields as the extra columns.
-- The case starts on the first open stage of the kind's pipeline.
create or replace function ${fn("open_case")}(tenant ${idType}, kind text, title text, description text default null, severity text default null, source text default 'internal', occurred_at timestamptz default null, owner_id uuid default null, due_on date default null, fields jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_kind uuid;
  v_row ${cases};
begin
  if not ${q.allowed("open_case.tenant", q.create)} then
    ${q.forbidden("not allowed to open cases")}
  end if;
  if open_case.fields is not null and jsonb_typeof(open_case.fields) <> 'object' then
    ${q.invalid("fields must be an object")}
  end if;
  perform ${fn("ensure_case_kinds")}(open_case.tenant);
  select x.${k("id")} into v_kind from ${kinds} x
  where x.${k("tenant")} = open_case.tenant and x.${k("key")} = open_case.kind;
  if not found then
    ${q.kindMissing}
  end if;
  v_row := ${fn("open_case_as")}(v_kind, jsonb_strip_nulls(jsonb_build_object(
    'title', open_case.title,
    'description', open_case.description,
    'severity', open_case.severity,
    'source', coalesce(open_case.source, 'internal'),
    'occurredAt', open_case.occurred_at,
    'ownerId', open_case.owner_id,
    'dueOn', open_case.due_on,
    'fields', open_case.fields
  )), auth.uid());
  return ${caseJson("v_row")};
end;
$$;
${userGrant(`${fn("open_case")}(${idType}, text, text, text, text, text, timestamptz, uuid, date, jsonb)`)}

-- A forms submission handler (blocks.forms.options.handlers): opens a case
-- from the answers kind (else options.intakeKind), title, description,
-- severity, source, occurredAt, name, email and phone. Forms calls it inside
-- its save, also for anonymous public forms, so it checks no permission.
create or replace function ${fn("case_from_submission")}(submission_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant ${idType};
  v_respondent uuid;
  v_answers jsonb;
  v_key text;
  v_kind ${kinds};
  v_input jsonb;
  v_row ${cases};
begin
  ${fromSubmission}
end;
$$;
${serviceGrant(`${fn("case_from_submission")}(uuid)`)}
`;
}

function changeFunctions(q: CasesSql): string {
  const { fn, c, cases, extras, caseJson } = q;

  const textColumn = (column: string, key: string): string =>
    q.has("cases", column)
      ? `\n    ${c(column)} = case when update_case.changes ? '${key}' then nullif(trim(update_case.changes ->> '${key}'), '') else x.${c(column)} end,`
      : "";

  const contact = q.has("cases", "reporterContact")
    ? `\n    ${c("reporterContact")} = case when update_case.changes ? 'reporterContact' then nullif(update_case.changes -> 'reporterContact', 'null'::jsonb) else x.${c("reporterContact")} end,`
    : "";

  const kindKey = (row: string): string =>
    `(select y.${q.k("key")} from ${q.kinds} y where y.${q.k("id")} = ${row}.${c("kind")})`;

  const editable = (name: string): string => `
  select * into v_row from ${cases} x where x.${c("id")} = ${name}.case_id for update;
  if not found then
    ${q.missing}
  end if;
  if not ${q.ownerOr("v_row", q.write)} then
    ${q.forbidden("not allowed to change this case")}
  end if;
  if v_row.${c("status")} <> 'open' then
    ${q.closed}
  end if;`;

  const statusEvents = `if v_row.${c("status")} is distinct from v_old.${c("status")} then
    if v_row.${c("status")} = 'closed' then
      ${q.record("case.closed", "v_row", kindKey("v_row"), "case closed", ", 'note', null")}
    elsif v_row.${c("status")} = 'canceled' then
      ${q.record("case.cancelled", "v_row", kindKey("v_row"), "case cancelled", ", 'reason', null")}
    else
      ${q.record("case.reopened", "v_row", kindKey("v_row"), "case reopened", ", 'reason', null")}
    end if;
  end if;`;

  return `
-- Changes a case's title, description, severity, source, owner, dates,
-- reporter contact or extra fields, or moves it: stageId to another stage of
-- its pipeline and rank to its place in the column. A move to a closing
-- stage, or out of one, needs cases.close and passes the close guard.
create or replace function ${fn("update_case")}(case_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${cases};
  v_old ${cases};
  v_title text;
  v_stage uuid;
  v_outcome text;
  v_changed text[];
  v_edited boolean;
begin
  select * into v_row from ${cases} x where x.${c("id")} = update_case.case_id for update;
  if not found then
    ${q.missing}
  end if;
  v_old := v_row;
  if not ${q.ownerOr("v_row", q.write)} then
    ${q.forbidden("not allowed to change this case")}
  end if;
  if jsonb_typeof(update_case.changes) is distinct from 'object' then
    ${q.invalid("changes must be an object")}
  end if;
  select coalesce(array_agg(key order by key), '{}') into v_changed from jsonb_object_keys(update_case.changes) key;
  v_edited := exists (select 1 from unnest(v_changed) key where key not in ('stageId', 'rank'));
  if exists (select 1 from unnest(v_changed) key where key not in (${UPDATE_KEYS})) then
    ${q.invalid("changes takes title, description, severity, source, ownerId, occurredAt, dueOn, reporterContact, fields, stageId and rank")}
  end if;
  v_stage := case when update_case.changes ? 'stageId' then (update_case.changes ->> 'stageId')::uuid else v_row.${c("stage")} end;
  if v_stage is null then
    ${q.invalid("stageId can't be null")}
  end if;
  if v_row.${c("status")} <> 'open' and (v_stage is not distinct from v_row.${c("stage")} or v_edited) then
    ${q.closed}
  end if;
  if v_stage is distinct from v_row.${c("stage")} then
    v_outcome := ${q.outcome("v_stage")};
    if (coalesce(v_outcome, 'open') <> 'open' or v_row.${c("status")} <> 'open') and not (
      case when v_outcome = 'success' and v_row.${c("status")} = 'open' then ${q.ownerOr("v_row", q.close)} else ${q.allowed(`v_row.${c("tenant")}`, q.close)} end
    ) then
      ${q.forbidden("not allowed to close, cancel or reopen cases")}
    end if;
  end if;
  if update_case.changes ? 'rank' and coalesce(update_case.changes ->> 'rank', '') !~ ${RANK_KEY_PATTERN} then
    ${q.invalid("rank must be a rank key")}
  end if;
  v_title := case when update_case.changes ? 'title' then trim(update_case.changes ->> 'title') else v_row.${c("title")} end;
  if coalesce(length(v_title), 0) not between 1 and 200 then
    ${q.invalid("a case needs a title of 1 to 200 characters")}
  end if;
  ${caseChecks(q, "update_case.changes")}
  update ${cases} x set
    ${c("title")} = v_title,${textColumn("description", "description")}${contact}
    ${c("severity")} = case when update_case.changes ? 'severity' then update_case.changes ->> 'severity' else x.${c("severity")} end,
    ${c("source")} = case when update_case.changes ? 'source' then update_case.changes ->> 'source' else x.${c("source")} end,
    ${c("owner")} = case when update_case.changes ? 'ownerId' then nullif(update_case.changes ->> 'ownerId', '')::uuid else x.${c("owner")} end,
    ${c("occurredAt")} = case when update_case.changes ? 'occurredAt' then nullif(update_case.changes ->> 'occurredAt', '')::timestamptz else x.${c("occurredAt")} end,
    ${c("dueOn")} = case when update_case.changes ? 'dueOn' then nullif(update_case.changes ->> 'dueOn', '')::date else x.${c("dueOn")} end,
    ${c("rank")} = case when update_case.changes ? 'rank' then update_case.changes ->> 'rank' else x.${c("rank")} end,
    ${c("stage")} = v_stage,
    ${c("updatedAt")} = now()
  where x.${c("id")} = v_row.${c("id")}
  returning * into v_row;${writeExtraColumns(cases, extras, "coalesce(update_case.changes -> 'fields', '{}'::jsonb)", `x.${c("id")} = v_row.${c("id")}`, "v_row")}
  if v_edited then
    ${q.record("case.updated", "v_row", kindKey("v_row"), "case updated", ", 'changed', to_jsonb(v_changed)")}
  end if;
  ${statusEvents}
  return ${caseJson("v_row")};
end;
$$;
${userGrant(`${fn("update_case")}(uuid, jsonb)`)}

-- Records the root cause, from text or an investigation form submission.
create or replace function ${fn("record_case_root_cause")}(case_id uuid, root_cause text, submission_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${cases};
begin${editable("record_case_root_cause")}
  if coalesce(length(trim(record_case_root_cause.root_cause)), 0) not between 1 and 10000 then
    ${q.invalid("a root cause is 1 to 10000 characters")}
  end if;
  update ${cases} x set
    ${c("rootCause")} = trim(record_case_root_cause.root_cause),
    ${c("rootCauseSubmission")} = coalesce(record_case_root_cause.submission_id, x.${c("rootCauseSubmission")}),
    ${c("updatedAt")} = now()
  where x.${c("id")} = v_row.${c("id")}
  returning * into v_row;
  ${q.record("case.root_cause_recorded", "v_row", kindKey("v_row"), "case root cause recorded", `, 'rootCause', v_row.${c("rootCause")}`)}
  return ${caseJson("v_row")};
end;
$$;
${userGrant(`${fn("record_case_root_cause")}(uuid, text, uuid)`)}

-- Records whether the actions worked, from a check or an effectiveness form
-- submission. A case of a kind that requires effectiveness closes only once
-- this is true.
create or replace function ${fn("record_case_effectiveness")}(case_id uuid, effective boolean, submission_id uuid default null, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${cases};
begin${editable("record_case_effectiveness")}
  if record_case_effectiveness.effective is null then
    ${q.invalid("effective is true or false")}
  end if;
  if length(record_case_effectiveness.note) > 4000 then
    ${q.invalid("note is at most 4000 characters")}
  end if;
  update ${cases} x set
    ${c("effective")} = record_case_effectiveness.effective,
    ${c("effectivenessNote")} = nullif(trim(record_case_effectiveness.note), ''),
    ${c("effectivenessSubmission")} = coalesce(record_case_effectiveness.submission_id, x.${c("effectivenessSubmission")}),
    ${c("updatedAt")} = now()
  where x.${c("id")} = v_row.${c("id")}
  returning * into v_row;
  ${q.record("case.effectiveness_recorded", "v_row", kindKey("v_row"), "case effectiveness recorded", `, 'effective', v_row.${c("effective")}, 'note', v_row.${c("effectivenessNote")}`)}
  return ${caseJson("v_row")};
end;
$$;
${userGrant(`${fn("record_case_effectiveness")}(uuid, boolean, uuid, text)`)}
`;
}

function actionFunctions(ctx: BlockSqlContext, q: CasesSql): string {
  const { fn, c, a, cases, actions, caseJson } = q;
  const tasks = q.tasks;
  const types = `array[${CASE_ACTION_TYPES.map((type) => `'${type}'`).join(", ")}]::text[]`;

  const kindKey = (row: string): string =>
    `(select y.${q.k("key")} from ${q.kinds} y where y.${q.k("id")} = ${row}.${c("kind")})`;

  const unavailable = fail(
    "CASE_TASKS_NOT_INSTALLED",
    "install the tasks block to give cases actions",
    "55000",
  );

  const load = (name: string): string => `
  select * into v_row from ${cases} x where x.${c("id")} = ${name}.case_id for update;
  if not found then
    ${q.missing}
  end if;
  if not ${q.ownerOr("v_row", q.write)} then
    ${q.forbidden("not allowed to change this case")}
  end if;
  if v_row.${c("status")} <> 'open' then
    ${q.closed}
  end if;
  if coalesce(${name}.type, '') <> all (${types}) then
    ${q.invalid("type is containment, correction, corrective, preventive or improvement")}
  end if;`;

  const created = (task: string): string =>
    q.record(
      "case_action.created",
      "v_row",
      kindKey("v_row"),
      "case action added",
      `, 'actionId', v_action.${a("id")}, 'taskId', ${task}, 'type', v_action.${a("type")}, 'required', v_action.${a("required")}`,
    );

  const link =
    tasks === undefined
      ? ""
      : createdFromLink(ctx, {
          tenant: `v_row.${c("tenant")}`,
          sourceType: sqlString(q.taskType),
          sourceId: "v_task::text",
          originType: q.subject,
          originId: `v_row.${c("id")}::text`,
        });

  const createBody =
    tasks === undefined
      ? unavailable
      : `${load("create_case_action")}
  if coalesce(length(trim(create_case_action.title)), 0) = 0 then
    ${q.invalid("an action needs a title")}
  end if;
  v_task := (${tasks.fn("create_task")}(v_row.${c("tenant")},
    jsonb_strip_nulls(jsonb_build_object('title', trim(create_case_action.title), 'dueAt', create_case_action.due_at)),
    case when create_case_action.assignee_id is null then '{}'::uuid[] else array[create_case_action.assignee_id] end
  ) ->> 'id')::uuid;
  insert into ${actions} (${a("tenant")}, ${a("case")}, ${a("task")}, ${a("type")}, ${a("required")})
  values (v_row.${c("tenant")}, v_row.${c("id")}, v_task, create_case_action.type, coalesce(create_case_action.required, true))
  returning * into v_action;
  ${link === "" ? "" : link}
  ${created("v_task")}
  return ${caseJson("v_row")} || jsonb_build_object('actionId', v_action.${a("id")}, 'taskId', v_task);`;

  const linkBody =
    tasks === undefined
      ? unavailable
      : `${load("link_case_action")}
  if not exists (
    select 1 from ${tasks.table("items")} i
    where i.${tasks.col("items", "id")} = link_case_action.task_id and i.${tasks.col("items", "tenant")}::text = v_row.${c("tenant")}::text
  ) then
    ${fail("CASE_INVALID", "no such work item in this organization", "P0002")}
  end if;
  begin
    insert into ${actions} (${a("tenant")}, ${a("case")}, ${a("task")}, ${a("type")}, ${a("required")})
    values (v_row.${c("tenant")}, v_row.${c("id")}, link_case_action.task_id, link_case_action.type, coalesce(link_case_action.required, true))
    returning * into v_action;
  exception when unique_violation then
    ${q.invalid("the work item is already an action of this case")}
  end;
  ${created("link_case_action.task_id")}
  perform ${fn("schedule_case_effectiveness")}(v_row.${c("id")});
  return ${caseJson("v_row")} || jsonb_build_object('actionId', v_action.${a("id")}, 'taskId', link_case_action.task_id);`;

  return `
-- Adds an action: a new work item with the title, assignee and due date,
-- linked to the case. Creating the work item needs the tasks permission too.
create or replace function ${fn("create_case_action")}(case_id uuid, type text, title text, assignee_id uuid default null, due_at timestamptz default null, required boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${cases};
  v_action ${actions};
  v_task uuid;
begin
  ${createBody}
end;
$$;
${userGrant(`${fn("create_case_action")}(uuid, text, text, uuid, timestamptz, boolean)`)}

-- Makes an existing work item an action of the case.
create or replace function ${fn("link_case_action")}(case_id uuid, task_id uuid, type text, required boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${cases};
  v_action ${actions};
begin
  ${linkBody}
end;
$$;
${userGrant(`${fn("link_case_action")}(uuid, uuid, text, boolean)`)}

-- Removes an action from its case; the work item stays.
create or replace function ${fn("remove_case_action")}(action_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_action ${actions};
  v_row ${cases};
begin
  select * into v_action from ${actions} x where x.${a("id")} = remove_case_action.action_id;
  if not found then
    ${fail("CASE_ACTION_NOT_FOUND", "no such case action", "P0002")}
  end if;
  select * into v_row from ${cases} x where x.${c("id")} = v_action.${a("case")} for update;
  if not ${q.ownerOr("v_row", q.write)} then
    ${q.forbidden("not allowed to change this case")}
  end if;
  if v_row.${c("status")} <> 'open' then
    ${q.closed}
  end if;
  delete from ${actions} x where x.${a("id")} = v_action.${a("id")};
  perform ${fn("schedule_case_effectiveness")}(v_row.${c("id")});
  ${q.record("case_action.deleted", "v_row", kindKey("v_row"), "case action removed", `, 'actionId', v_action.${a("id")}, 'taskId', v_action.${a("task")}, 'type', v_action.${a("type")}`)}
  return ${caseJson("v_row")};
end;
$$;
${userGrant(`${fn("remove_case_action")}(uuid)`)}
`;
}

export function caseFunctions(ctx: BlockSqlContext): string {
  const q = casesSql(ctx);

  return `${kindFunctions(ctx, q)}${openFunctions(ctx, q)}${changeFunctions(q)}${actionFunctions(ctx, q)}`;
}
