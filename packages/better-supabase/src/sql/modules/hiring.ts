import type { HiringEvents } from "../../blocks/hiring/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlString } from "../../core/template.ts";
import {
  addExtraColumns,
  fail,
  lockTable,
  schemaPreamble,
  triggerGrant,
  userGrant,
  withExtraFields,
  writeExtraColumns,
} from "../shared.ts";
import { subjectInTenant } from "../subject-check-sql.ts";
import { moduleOperations } from "./access-model.ts";

const APPLICATION = [
  "organizationId",
  "applicationId",
  "subjectType",
  "subjectId",
  "jobId",
  "candidateType",
  "candidateId",
] as const;

const EVENTS: BlockSqlEvents<HiringEvents> = {
  "job.opened": {
    subject: "jobs",
    payload: ["organizationId", "jobId", "title"],
  },
  "job.closed": {
    subject: "jobs",
    payload: ["organizationId", "jobId", "title"],
  },
  "application.created": { subject: "applications", payload: [...APPLICATION] },
  "application.hired": { subject: "applications", payload: [...APPLICATION] },
  "application.rejected": {
    subject: "applications",
    payload: [...APPLICATION, "reason"],
  },
  "application.retracted": {
    subject: "applications",
    payload: [...APPLICATION],
  },
  "scorecard.submitted": {
    subject: "applications",
    payload: [...APPLICATION, "reviewerId", "recommendation"],
  },
  "interview.scheduled": {
    subject: "applications",
    payload: [...APPLICATION, "interviewId", "startsAt"],
  },
};

const NAMES: BlockSqlNames = {
  events: EVENTS,
  hooks: ["before_application_hire", "after_application_hire"],
  options: ["candidate", "extraColumns"],
  tables: {
    jobs: {
      name: "jobs",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        title: "title",
        team: "team_id",
        location: "location",
        employmentType: "employment_type",
        description: "description",
        hiringManager: "hiring_manager_user_id",
        status: "status",
        openedAt: "opened_at",
        closedAt: "closed_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    applications: {
      name: "applications",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        job: "job_id",
        candidateType: "candidate_type",
        candidateId: "candidate_id",
        source: "source",
        owner: "owner_user_id",
        pipeline: "pipeline_id",
        stage: "stage_id",
        stageEnteredAt: "stage_entered_at",
        state: "state",
        rejectionReason: "rejection_reason",
        hiredAt: "hired_at",
        rank: "rank",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    scorecards: {
      name: "application_scorecards",
      lifecycle: { tenant: "tenant", user: "reviewer", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        application: "application_id",
        stage: "stage_id",
        reviewer: "reviewer_user_id",
        rating: "rating",
        recommendation: "recommendation",
        notes: "notes",
        submittedAt: "submitted_at",
      },
    },
    interviews: {
      name: "interviews",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        application: "application_id",
        kind: "kind",
        startsAt: "starts_at",
        endsAt: "ends_at",
        location: "location",
        interviewers: "interviewer_user_ids",
        createdBy: "created_by",
        createdAt: "created_at",
      },
    },
  },
};

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const keys = moduleOperations("hiring");
  const read = ctx.permission("read", keys.read);
  const write = ctx.permission("write", keys.write);
  const manage = ctx.permission("manage", keys.manage);
  const candidate = ctx.text("candidate", "person");
  const extras = ctx.extraColumns("jobs");
  const fn = (name: string): string => ctx.fn(name);
  const t = (table: string): string => ctx.table(table);
  const j = (column: string): string => ctx.col("jobs", column);
  const a = (column: string): string => ctx.col("applications", column);
  const s = (column: string): string => ctx.col("scorecards", column);
  const v = (column: string): string => ctx.col("interviews", column);
  const service = "(auth.role() = 'service_role')";
  const pipelines = ctx.of("pipelines");
  const st = (column: string): string => pipelines.col("stages", column);

  const payload = (alias: string, extra = ""): string =>
    `jsonb_build_object('organizationId', ${alias}.${a("tenant")}, 'applicationId', ${alias}.${a("id")}, 'subjectType', 'application', 'subjectId', ${alias}.${a("id")}::text, 'jobId', ${alias}.${a("job")}, 'candidateType', ${alias}.${a("candidateType")}, 'candidateId', ${alias}.${a("candidateId")}${extra})`;

  const record = (type: string, alias: string, extra = ""): string =>
    ctx.record({
      type,
      payload: payload(alias, extra),
      subject: `'applications/' || ${alias}.${a("id")}::text`,
      tenant: `${alias}.${a("tenant")}::text`,
      audit: false,
    });

  const jobRecord = (type: string): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', v_job.${j("tenant")}, 'jobId', v_job.${j("id")}, 'title', v_job.${j("title")})`,
      subject: `'jobs/' || v_job.${j("id")}::text`,
      tenant: `v_job.${j("tenant")}::text`,
      audit: false,
    });

  const moveTo = (outcome: string, category: string): string => `
  select x.${st("id")} into v_stage from ${pipelines.table("stages")} x
  where x.${st("pipeline")} = v_row.${a("pipeline")} and x.${st("archivedAt")} is null
    and x.${st("outcome")} = ${sqlString(outcome)} and x.${st("category")} = ${sqlString(category)}
  order by x.${st("rank")} collate "C" limit 1;
  if v_stage is null then
    ${fail("HIRING_STAGE_MISSING", "the job's pipeline has no stage for that", "P0002")}
  end if;
  update ${t("applications")} x set ${a("stage")} = v_stage where x.${a("id")} = v_row.${a("id")};`;

  const editable = (tenant: string): string =>
    `(${service} or ${ctx.scope.can(tenant, write)})`;

  const tables = ctx.manages
    ? `
create table if not exists ${t("jobs")} (
  ${j("id")} uuid primary key default gen_random_uuid(),
  ${j("tenant")} ${ctx.idType} not null,
  ${j("title")} text not null check (length(${j("title")}) between 1 and 200),
  ${j("team")} uuid,
  ${j("location")} text,
  ${j("employmentType")} text,
  ${j("description")} text,
  ${j("hiringManager")} uuid,
  ${j("status")} text not null default 'draft' check (${j("status")} in ('draft', 'open', 'closed')),
  ${j("openedAt")} timestamptz,
  ${j("closedAt")} timestamptz,
  ${j("createdAt")} timestamptz not null default now(),
  ${j("updatedAt")} timestamptz not null default now()
);
create index if not exists jobs_tenant_status_idx on ${t("jobs")} (${j("tenant")}, ${j("status")});${addExtraColumns(t("jobs"), extras)}
${lockTable(t("jobs"), { read: true })}
drop policy if exists jobs_read on ${t("jobs")};
create policy jobs_read on ${t("jobs")} for select to authenticated
using (${ctx.scope.check(j("tenant"), read)});

create table if not exists ${t("applications")} (
  ${a("id")} uuid primary key default gen_random_uuid(),
  ${a("tenant")} ${ctx.idType} not null,
  ${a("job")} uuid not null references ${t("jobs")} (${j("id")}) on delete cascade,
  ${a("candidateType")} text not null,
  ${a("candidateId")} text not null,
  ${a("source")} text,
  ${a("owner")} uuid,
  ${a("pipeline")} uuid,
  ${a("stage")} uuid,
  ${a("stageEnteredAt")} timestamptz,
  ${a("state")} text not null default 'active' check (${a("state")} in ('active', 'hired', 'rejected', 'withdrawn')),
  ${a("rejectionReason")} text,
  ${a("hiredAt")} timestamptz,
  ${a("rank")} text collate "C" not null default 'V',
  ${a("createdAt")} timestamptz not null default now(),
  ${a("updatedAt")} timestamptz not null default now(),
  unique (${a("job")}, ${a("candidateType")}, ${a("candidateId")})
);
create index if not exists applications_board_idx on ${t("applications")} (${a("pipeline")}, ${a("stage")}, ${a("rank")});
create index if not exists applications_candidate_idx on ${t("applications")} (${a("candidateType")}, ${a("candidateId")});
${lockTable(t("applications"), { read: true })}
drop policy if exists applications_read on ${t("applications")};
create policy applications_read on ${t("applications")} for select to authenticated
using (${ctx.scope.check(a("tenant"), read)});

create table if not exists ${t("scorecards")} (
  ${s("id")} uuid primary key default gen_random_uuid(),
  ${s("tenant")} ${ctx.idType} not null,
  ${s("application")} uuid not null references ${t("applications")} (${a("id")}) on delete cascade,
  ${s("stage")} uuid,
  ${s("reviewer")} uuid not null,
  ${s("rating")} smallint not null check (${s("rating")} between 1 and 4),
  ${s("recommendation")} text not null check (${s("recommendation")} in ('strong_no', 'no', 'yes', 'strong_yes')),
  ${s("notes")} text,
  ${s("submittedAt")} timestamptz not null default now(),
  unique nulls not distinct (${s("application")}, ${s("stage")}, ${s("reviewer")})
);
create index if not exists application_scorecards_reviewer_idx on ${t("scorecards")} (${s("reviewer")});
${lockTable(t("scorecards"), { read: true })}
drop policy if exists application_scorecards_read on ${t("scorecards")};
create policy application_scorecards_read on ${t("scorecards")} for select to authenticated
using (${ctx.scope.check(s("tenant"), read)});

create table if not exists ${t("interviews")} (
  ${v("id")} uuid primary key default gen_random_uuid(),
  ${v("tenant")} ${ctx.idType} not null,
  ${v("application")} uuid not null references ${t("applications")} (${a("id")}) on delete cascade,
  ${v("kind")} text,
  ${v("startsAt")} timestamptz not null,
  ${v("endsAt")} timestamptz not null,
  ${v("location")} text,
  ${v("interviewers")} uuid[] not null default '{}',
  ${v("createdBy")} uuid,
  ${v("createdAt")} timestamptz not null default now(),
  check (${v("endsAt")} > ${v("startsAt")})
);
create index if not exists interviews_application_idx on ${t("interviews")} (${v("application")}, ${v("startsAt")});
${lockTable(t("interviews"), { read: true })}
drop policy if exists interviews_read on ${t("interviews")};
create policy interviews_read on ${t("interviews")} for select to authenticated
using (${ctx.scope.check(v("tenant"), read)} or (select auth.uid()) = any (${v("interviewers")}));
`
    : "";

  return `${schemaPreamble(ctx)}
-- Hiring: jobs, applications on a pipeline per job, scorecards per stage,
-- interviews, and a hire event the app turns into an employee.
${tables}
-- A rejected, withdrawn or hired application records its event and its
-- time; reopening clears them.
create or replace function better_supabase.bsb_application_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.${a("state")} is not distinct from old.${a("state")} then
    new.${a("updatedAt")} := now();
    return new;
  end if;
  new.${a("hiredAt")} := case when new.${a("state")} = 'hired' then now() end;
  if new.${a("state")} <> 'rejected' then
    new.${a("rejectionReason")} := null;
  end if;
  case new.${a("state")}
    when 'hired' then ${record("application.hired", "new")}
    when 'rejected' then ${record("application.rejected", "new", `, 'reason', new.${a("rejectionReason")}`)}
    when 'withdrawn' then ${record("application.retracted", "new")}
    else null;
  end case;
  new.${a("updatedAt")} := now();
  return new;
end;
$$;
${triggerGrant("better_supabase.bsb_application_guard()")}
drop trigger if exists bsb_application_guard on ${t("applications")};
create trigger bsb_application_guard before update of ${a("state")} on ${t("applications")}
for each row execute function better_supabase.bsb_application_guard();

-- Creates or changes a job: title, teamId, location, employmentType,
-- description, hiringManagerId, fields (the extra columns by name); and
-- status draft, open or closed.
create or replace function ${fn("save_job")}(tenant ${ctx.idType}, job uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job ${t("jobs")};
  v_was text;
begin
  if not (${service} or ${ctx.scope.can("save_job.tenant", manage)}) then
    ${fail("HIRING_FORBIDDEN", "not allowed to manage jobs")}
  end if;
  if save_job.job is not null then
    select * into v_job from ${t("jobs")} x where x.${j("id")} = save_job.job and x.${j("tenant")} = save_job.tenant;
    if v_job.${j("id")} is null then
      ${fail("HIRING_JOB_NOT_FOUND", "job not found", "P0002")}
    end if;
    v_was := v_job.${j("status")};
  end if;
  begin
    if save_job.job is null then
      insert into ${t("jobs")} (${j("tenant")}, ${j("title")}, ${j("team")}, ${j("location")}, ${j("employmentType")}, ${j("description")}, ${j("hiringManager")}, ${j("status")})
      values (save_job.tenant, save_job.attrs ->> 'title', (save_job.attrs ->> 'teamId')::uuid, save_job.attrs ->> 'location',
        save_job.attrs ->> 'employmentType', save_job.attrs ->> 'description', (save_job.attrs ->> 'hiringManagerId')::uuid,
        coalesce(save_job.attrs ->> 'status', 'draft'))
      returning * into v_job;
    else
      update ${t("jobs")} x set
        ${j("title")} = coalesce(save_job.attrs ->> 'title', x.${j("title")}),
        ${j("team")} = case when save_job.attrs ? 'teamId' then (save_job.attrs ->> 'teamId')::uuid else x.${j("team")} end,
        ${j("location")} = case when save_job.attrs ? 'location' then save_job.attrs ->> 'location' else x.${j("location")} end,
        ${j("employmentType")} = case when save_job.attrs ? 'employmentType' then save_job.attrs ->> 'employmentType' else x.${j("employmentType")} end,
        ${j("description")} = case when save_job.attrs ? 'description' then save_job.attrs ->> 'description' else x.${j("description")} end,
        ${j("hiringManager")} = case when save_job.attrs ? 'hiringManagerId' then (save_job.attrs ->> 'hiringManagerId')::uuid else x.${j("hiringManager")} end,
        ${j("status")} = coalesce(save_job.attrs ->> 'status', x.${j("status")}),
        ${j("updatedAt")} = now()
      where x.${j("id")} = save_job.job
      returning * into v_job;
    end if;
  exception when check_violation or not_null_violation or invalid_text_representation then
    ${fail("HIRING_JOB_INVALID", "a job needs a title and a status of draft, open or closed", "22023")}
  end;${writeExtraColumns(t("jobs"), extras, "save_job.attrs -> 'fields'", `x.${j("id")} = v_job.${j("id")}`, "v_job")}
  if v_job.${j("status")} is distinct from v_was then
    if v_job.${j("status")} = 'open' then
      update ${t("jobs")} x set ${j("openedAt")} = coalesce(x.${j("openedAt")}, now()), ${j("closedAt")} = null where x.${j("id")} = v_job.${j("id")} returning * into v_job;
      ${jobRecord("job.opened")}
    elsif v_job.${j("status")} = 'closed' then
      update ${t("jobs")} x set ${j("closedAt")} = now() where x.${j("id")} = v_job.${j("id")} returning * into v_job;
      ${jobRecord("job.closed")}
    end if;
  end if;
  return ${withExtraFields("to_jsonb(v_job)", "v_job", extras)};
end;
$$;
${userGrant(`${fn("save_job")}(${ctx.idType}, uuid, jsonb)`)}

-- An application of a candidate (a record in config.records, a person by
-- default) to an open job. Applying again returns the same application.
create or replace function ${fn("apply_to_job")}(job uuid, candidate jsonb, source text, owner uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job ${t("jobs")};
  v_row ${t("applications")};
  v_type text := coalesce(apply_to_job.candidate ->> 'type', ${sqlString(candidate)});
  v_id text := apply_to_job.candidate ->> 'id';
begin
  select * into v_job from ${t("jobs")} x where x.${j("id")} = apply_to_job.job;
  if v_job.${j("id")} is null or not ${editable(`v_job.${j("tenant")}`)} then
    ${fail("HIRING_JOB_NOT_FOUND", "no such job you can add applications to", "P0002")}
  end if;
  if v_job.${j("status")} <> 'open' then
    ${fail("HIRING_JOB_NOT_OPEN", "the job isn't open", "55000")}
  end if;
  if v_id is null or not ${subjectInTenant(ctx, "v_type", "v_id", `v_job.${j("tenant")}`)} then
    ${fail("HIRING_CANDIDATE_FORBIDDEN", "the candidate is unknown or not readable in this organization", "42501")}
  end if;
  select * into v_row from ${t("applications")} x
  where x.${a("job")} = v_job.${j("id")} and x.${a("candidateType")} = v_type and x.${a("candidateId")} = v_id;
  if v_row.${a("id")} is not null then
    return to_jsonb(v_row);
  end if;
  insert into ${t("applications")} (${a("tenant")}, ${a("job")}, ${a("candidateType")}, ${a("candidateId")}, ${a("source")}, ${a("owner")})
  values (v_job.${j("tenant")}, v_job.${j("id")}, v_type, v_id, nullif(trim(apply_to_job.source), ''), coalesce(apply_to_job.owner, auth.uid()))
  returning * into v_row;
  ${record("application.created", "v_row")}
  return to_jsonb(v_row);
end;
$$;
${userGrant(`${fn("apply_to_job")}(uuid, jsonb, text, uuid)`)}

-- Ends an application: hired, rejected (with a reason) or withdrawn. It
-- moves to the job pipeline's first stage of that category.
create or replace function ${fn("close_application")}(application uuid, outcome text, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("applications")};
  v_stage uuid;
begin
  select * into v_row from ${t("applications")} x where x.${a("id")} = close_application.application;
  if v_row.${a("id")} is null or not ${editable(`v_row.${a("tenant")}`)} then
    ${fail("HIRING_APPLICATION_NOT_FOUND", "no such application you can change", "P0002")}
  end if;
  if close_application.outcome not in ('hired', 'rejected', 'withdrawn') then
    ${fail("HIRING_OUTCOME_INVALID", "close as hired, rejected or withdrawn", "22023")}
  end if;
  if close_application.outcome = 'hired' then
    ${ctx.hook("before_application_hire", [["uuid", `v_row.${a("id")}`]])}
  end if;
  update ${t("applications")} x set ${a("rejectionReason")} = nullif(trim(close_application.reason), '') where x.${a("id")} = v_row.${a("id")};
  case close_application.outcome
    when 'hired' then ${moveTo("success", "hired")}
    when 'rejected' then ${moveTo("failure", "rejected")}
    else ${moveTo("failure", "withdrawn")}
  end case;
  if close_application.outcome = 'hired' then
    ${ctx.hook("after_application_hire", [["uuid", `v_row.${a("id")}`]])}
  end if;
  return (select to_jsonb(x) from ${t("applications")} x where x.${a("id")} = v_row.${a("id")});
end;
$$;
${userGrant(`${fn("close_application")}(uuid, text, text)`)}

-- The caller's scorecard on an application at its current stage: a rating
-- from 1 to 4 and a recommendation. Submitting again replaces it.
create or replace function ${fn("submit_scorecard")}(application uuid, rating integer, recommendation text, notes text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("applications")};
  v_card ${t("scorecards")};
begin
  select * into v_row from ${t("applications")} x where x.${a("id")} = submit_scorecard.application;
  if v_row.${a("id")} is null or not (${editable(`v_row.${a("tenant")}`)} or exists (
    select 1 from ${t("interviews")} y where y.${v("application")} = v_row.${a("id")} and auth.uid() = any (y.${v("interviewers")}))) then
    ${fail("HIRING_APPLICATION_NOT_FOUND", "no such application you can review", "P0002")}
  end if;
  begin
    insert into ${t("scorecards")} (${s("tenant")}, ${s("application")}, ${s("stage")}, ${s("reviewer")}, ${s("rating")}, ${s("recommendation")}, ${s("notes")})
    values (v_row.${a("tenant")}, v_row.${a("id")}, v_row.${a("stage")}, auth.uid(), submit_scorecard.rating, submit_scorecard.recommendation, submit_scorecard.notes)
    on conflict (${s("application")}, ${s("stage")}, ${s("reviewer")}) do update set
      ${s("rating")} = excluded.${s("rating")}, ${s("recommendation")} = excluded.${s("recommendation")},
      ${s("notes")} = excluded.${s("notes")}, ${s("submittedAt")} = now()
    returning * into v_card;
  exception when check_violation or not_null_violation then
    ${fail("HIRING_SCORECARD_INVALID", "a scorecard needs a rating from 1 to 4 and a recommendation", "22023")}
  end;
  ${record("scorecard.submitted", "v_row", `, 'reviewerId', v_card.${s("reviewer")}, 'recommendation', v_card.${s("recommendation")}`)}
  return to_jsonb(v_card);
end;
$$;
${userGrant(`${fn("submit_scorecard")}(uuid, integer, text, text)`)}

-- Schedules an interview; the interviewers can read it and score the
-- application.
create or replace function ${fn("schedule_interview")}(application uuid, starts_at timestamptz, ends_at timestamptz, interviewers uuid[], kind text, location text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("applications")};
  v_interview ${t("interviews")};
begin
  select * into v_row from ${t("applications")} x where x.${a("id")} = schedule_interview.application;
  if v_row.${a("id")} is null or not ${editable(`v_row.${a("tenant")}`)} then
    ${fail("HIRING_APPLICATION_NOT_FOUND", "no such application you can change", "P0002")}
  end if;
  begin
    insert into ${t("interviews")} (${v("tenant")}, ${v("application")}, ${v("kind")}, ${v("startsAt")}, ${v("endsAt")}, ${v("location")}, ${v("interviewers")}, ${v("createdBy")})
    values (v_row.${a("tenant")}, v_row.${a("id")}, schedule_interview.kind, schedule_interview.starts_at, schedule_interview.ends_at,
      schedule_interview.location, coalesce(schedule_interview.interviewers, '{}'), auth.uid())
    returning * into v_interview;
  exception when check_violation or not_null_violation then
    ${fail("HIRING_INTERVIEW_INVALID", "an interview needs a start before its end", "22023")}
  end;
  ${record("interview.scheduled", "v_row", `, 'interviewId', v_interview.${v("id")}, 'startsAt', v_interview.${v("startsAt")}`)}
  return to_jsonb(v_interview);
end;
$$;
${userGrant(`${fn("schedule_interview")}(uuid, timestamptz, timestamptz, uuid[], text, text)`)}

-- An application with its scorecards and interviews, and the average
-- rating and recommendations per stage.
create or replace function ${fn("application_detail")}(application uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object(
    'scorecards', coalesce((select jsonb_agg(to_jsonb(c) order by c.${s("submittedAt")}) from ${t("scorecards")} c where c.${s("application")} = x.${a("id")}), '[]'::jsonb),
    'interviews', coalesce((select jsonb_agg(to_jsonb(i) order by i.${v("startsAt")}) from ${t("interviews")} i where i.${v("application")} = x.${a("id")}), '[]'::jsonb),
    'averageRating', (select round(avg(c.${s("rating")}), 2) from ${t("scorecards")} c where c.${s("application")} = x.${a("id")}))
  from ${t("applications")} x where x.${a("id")} = application_detail.application
$$;
${userGrant(`${fn("application_detail")}(uuid)`)}
`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    { name: "save_job", args: ["{id}", "uuid", "jsonb"], returns: "jsonb" },
    {
      name: "apply_to_job",
      args: ["uuid", "jsonb", "text", "uuid"],
      returns: "jsonb",
    },
    {
      name: "close_application",
      args: ["uuid", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "submit_scorecard",
      args: ["uuid", "integer", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "schedule_interview",
      args: ["uuid", "timestamptz", "timestamptz", "uuid[]", "text", "text"],
      returns: "jsonb",
    },
    { name: "application_detail", args: ["uuid"], returns: "jsonb" },
  ];
}

export const HIRING: BlockSqlDefinition = {
  name: "hiring",
  scopes: ["tenant"],
  title: "Hiring",
  description:
    "Jobs and applications on a pipeline per job, candidates from config.records, scorecards per stage, interviews, and hire, reject and withdraw events for the app to act on.",
  requires: ["tenant", "access", "subjects", "pipelines"],
  // The pipelines module binds the applications table, so the table comes first.
  before: "pipelines",
  integrates: ["outbox"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
