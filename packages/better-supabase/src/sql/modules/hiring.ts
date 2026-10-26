import type { HiringEvents } from "../../blocks/hiring/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockContributes } from "../contributions.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { APPLICATION_TO_EMPLOYEE } from "../../blocks/hiring/automations.ts";
import { sqlString } from "../../core/template.ts";
import { asColumnType } from "../column-type.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  addExtraColumns,
  fail,
  insertExtraColumns,
  schemaPreamble,
  triggerGrant,
  userGrant,
  withExtraFields,
  writeExtraColumns,
} from "../shared.ts";
import { subjectInTenant } from "../subject-check-sql.ts";
import { shippedAutomation } from "./automation-defaults.ts";
import {
  candidateSubjectIdType,
  choice,
  hiringCandidate,
  interviewersTable,
  managerCheck,
  optIn,
  reviewable,
  scoresTable,
  scoresWrite,
} from "./hiring-adoption.ts";
import { closeInStages, jobStages, stageTriggers } from "./hiring-stages.ts";
import { appUniqueIndex, asText, lockModuleTable } from "./over-app.ts";
import { moduleOperations } from "./permissions-model.ts";

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

/** The optional job columns `save_job` writes: logical, attrs key, and name. */
const JOB_ATTRS: readonly (readonly [string, string, string])[] = [
  ["team", "teamId", "team"],
  ["location", "location", "location"],
  ["employmentType", "employmentType", "employment type"],
  ["description", "description", "description"],
  ["hiringManager", "hiringManagerId", "hiring manager"],
];

const NAMES: BlockSqlNames = {
  entities: {
    job: { table: "jobs", singular: "job_opening", primary: true },
    application: { table: "applications", singular: "application" },
    interview: { table: "interviews", singular: "interview" },
  },
  events: EVENTS,
  hooks: ["before_application_hire", "after_application_hire"],
  options: [
    "candidate",
    "extraColumns",
    "stages",
    "scorecardKey",
    "hiringManager",
  ],
  tables: {
    jobs: {
      name: "job_openings",
      app: {},
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
      optional: [
        "team",
        "location",
        "employmentType",
        "description",
        "hiringManager",
        "openedAt",
        "closedAt",
      ],
      typed: ["status"],
      mappable: ["employmentType"],
    },
    applications: {
      name: "applications",
      app: {},
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
      optional: [
        "source",
        "owner",
        "stageEnteredAt",
        "rejectionReason",
        "hiredAt",
        "candidateType",
        "pipeline",
      ],
      typed: ["state"],
      mappable: ["source"],
    },
    scorecards: {
      name: "application_scorecards",
      app: {},
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
      optional: ["notes", "recommendation", "stage"],
      typed: ["recommendation"],
    },
    interviews: {
      name: "interviews",
      app: {},
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
      optional: ["kind", "location", "createdBy", "interviewers"],
      mappable: ["kind"],
    },
    interviewers: {
      name: "interview_interviewers",
      optionalTable: true,
      app: { onlyWhenMapped: true },
      columns: {
        tenant: "tenant_id",
        interview: "interview_id",
        user: "user_id",
      },
      optional: ["tenant"],
    },
    scorecardScores: {
      name: "application_scorecard_scores",
      optionalTable: true,
      app: { onlyWhenMapped: true },
      columns: {
        tenant: "tenant_id",
        scorecard: "scorecard_id",
        criterion: "criterion_key",
        score: "score",
        notes: "notes",
      },
      optional: ["tenant", "notes"],
    },
  },
  migrations: [
    {
      from: 1,
      description:
        "The jobs table is job_openings, so it doesn't read as the queue block's jobs.",
      table: "jobs",
      was: "jobs",
    },
  ],
};

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const keys = moduleOperations("hiring");
  const read = ctx.permission("read", keys.read);
  const write = ctx.permission("write", keys.write);
  const manage = ctx.permission("manage", keys.manage);
  const writeKey = ctx.permissionKey("write", keys.write);
  const manageKey = ctx.permissionKey("manage", keys.manage);
  const createKey = sqlString(ctx.config.permissions["create"] ?? writeKey);
  const scoreKey = sqlString(ctx.config.permissions["score"] ?? writeKey);
  const jobsCreate = ctx.config.permissions["jobsCreate"];
  const jobsUpdate = ctx.config.permissions["jobsUpdate"];
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
  const iv = (column: string): string => ctx.col("interviewers", column);
  const sc = (column: string): string => ctx.col("scorecardScores", column);
  const stages = jobStages(ctx);
  const fixedCandidate = !ctx.has("applications", "candidateType");
  const interviewerRows = optIn(ctx, "interviewers");
  const scoreRows = optIn(ctx, "scorecardScores");
  const pipelined = stages === undefined && ctx.has("applications", "pipeline");

  const perApplication =
    choice(ctx, "scorecardKey", ["stage", "application"]) === "application" ||
    !ctx.has("scorecards", "stage");

  const managerEmployee =
    choice(ctx, "hiringManager", ["user", "employee"]) === "employee";

  const candidateIdType = fixedCandidate
    ? candidateSubjectIdType(ctx, candidate)
    : "text";

  const candidateType = (row: string): string => hiringCandidate(ctx, row).type;

  const candidateId = (row: string): string => hiringCandidate(ctx, row).id;

  const candidateValue = (value: string): string =>
    fixedCandidate
      ? asColumnType(
          t("applications"),
          ctx.colName("applications", "candidateId"),
          value,
        )
      : value;

  const applicationJson = (alias: string): string =>
    fixedCandidate
      ? `(${ctx.rowJson("applications", alias, { as: { candidateId: (value) => `${value}::text` } })} || jsonb_build_object('candidate_type', ${sqlString(candidate)}, ${sqlString(ctx.colName("applications", "candidateId"))}, ${alias}.${a("candidateId")}::text))`
      : ctx.rowJson("applications", alias);

  const interviewerOf = (row: string, user: string): string | undefined => {
    const checks = [
      ...(ctx.has("interviews", "interviewers")
        ? [`${user} = any (${row}.${v("interviewers")})`]
        : []),
      ...(interviewerRows
        ? [
            `exists (select 1 from ${t("interviewers")} z where z.${iv("interview")} = ${row}.${v("id")} and z.${iv("user")} = ${user})`,
          ]
        : []),
    ];

    if (checks.length <= 1) {
      return checks[0];
    }

    return `(${checks.join(" or ")})`;
  };

  const interviewJson = (alias: string): string =>
    interviewerRows
      ? `(${ctx.rowJson("interviews", alias)} || jsonb_build_object('interviewer_user_ids', (select coalesce(jsonb_agg(z.${iv("user")} order by z.${iv("user")}), '[]'::jsonb) from ${t("interviewers")} z where z.${iv("interview")} = ${alias}.${v("id")})))`
      : ctx.rowJson("interviews", alias);

  const scorecardJson = (alias: string): string =>
    scoreRows
      ? `(${ctx.rowJson("scorecards", alias)} || jsonb_build_object('scores', (select coalesce(jsonb_agg(jsonb_build_object('criterion', y.${sc("criterion")}, 'score', y.${sc("score")}, 'notes', ${ctx.has("scorecardScores", "notes") ? `y.${sc("notes")}` : "null"}) order by y.${sc("criterion")}), '[]'::jsonb) from ${t("scorecardScores")} y where y.${sc("scorecard")} = ${alias}.${s("id")})))`
      : ctx.rowJson("scorecards", alias);

  const managerValue =
    managerEmployee && ctx.has("jobs", "hiringManager")
      ? asColumnType(
          t("jobs"),
          ctx.colName("jobs", "hiringManager"),
          "save_job.attrs ->> 'hiringManagerId'",
        )
      : "(save_job.attrs ->> 'hiringManagerId')::uuid";

  // A column definition, left out when the app maps the column to null.
  const column = (table: string, logical: string, type: string): string =>
    ctx.has(table, logical) ? `\n  ${ctx.col(table, logical)} ${type},` : "";

  // A column of row, or null when the app maps it to null.
  const or = (table: string, row: string, logical: string): string =>
    ctx.has(table, logical) ? `${row}.${ctx.col(table, logical)}` : "null";

  // ", <column>" for an insert's column list, when the column exists.
  const also = (table: string, logical: string): string =>
    ctx.has(table, logical) ? `, ${ctx.col(table, logical)}` : "";

  // ", <value>" matching also().
  const alsoValue = (table: string, logical: string, value: string): string =>
    ctx.has(table, logical) ? `, ${value}` : "";

  // value when the column exists, for lines().
  const present = (
    table: string,
    logical: string,
    value: string,
  ): string | undefined => (ctx.has(table, logical) ? value : undefined);

  // The values of an insert, the present ones of each group on a line.
  const lines = (
    indent: string,
    ...groups: readonly (string | undefined)[][]
  ): string =>
    groups
      .map((group) => group.filter((value) => value !== undefined).join(", "))
      .filter((line) => line !== "")
      .join(`,\n${indent}`);

  // Refuses a non-null `value` for a column the app maps to null.
  const refuse = (
    table: string,
    logical: string,
    value: string,
    code: string,
    message: string,
    indent = "  ",
  ): string =>
    ctx.has(table, logical)
      ? ""
      : `\n${indent}if ${value} is not null then
${indent}  ${fail(code, message, "22023")}
${indent}end if;`;

  // A job column save_job keeps unless attrs has its key.
  const keep = (logical: string, key: string, value: string): string =>
    ctx.has("jobs", logical)
      ? `\n        ${j(logical)} = case when save_job.attrs ? '${key}' then ${value} else x.${j(logical)} end,`
      : "";

  // The update that stamps a job's open and close times, when it has them.
  const stamp = (sets: readonly (string | undefined)[]): string => {
    const kept = sets.filter((set) => set !== undefined);

    return kept.length === 0
      ? ""
      : `\n      update ${t("jobs")} x set ${kept.join(", ")} where x.${j("id")} = v_job.${j("id")} returning * into v_job;`;
  };

  const payload = (alias: string, extra = ""): string =>
    `jsonb_build_object('organizationId', ${alias}.${a("tenant")}, 'applicationId', ${alias}.${a("id")}, 'subjectType', 'application', 'subjectId', ${alias}.${a("id")}::text, 'jobId', ${alias}.${a("job")}, 'candidateType', ${candidateType(alias)}, 'candidateId', ${candidateId(alias)}${extra})`;

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

  const jobAccess =
    jobsCreate === undefined && jobsUpdate === undefined
      ? ctx.scope.can("save_job.tenant", manage)
      : `((save_job.job is null and ${ctx.scope.can("save_job.tenant", sqlString(jobsCreate ?? manageKey))}) or (save_job.job is not null and ${ctx.scope.can("save_job.tenant", sqlString(jobsUpdate ?? manageKey))}))`;

  const requiredJobColumns = insertExtraColumns(
    t("jobs"),
    extras,
    "save_job.attrs -> 'fields'",
  );

  const tables = ctx.manages
    ? `
create table if not exists ${t("jobs")} (
  ${j("id")} uuid primary key default gen_random_uuid(),
  ${j("tenant")} ${ctx.idType} not null,
  ${j("title")} text not null check (length(${j("title")}) between 1 and 200),${column("jobs", "team", "uuid")}${column("jobs", "location", "text")}${column("jobs", "employmentType", "text")}${column("jobs", "description", "text")}${column("jobs", "hiringManager", "uuid")}
  ${j("status")} text not null default 'draft' check (${j("status")} in ('draft', 'open', 'closed')),${column("jobs", "openedAt", "timestamptz")}${column("jobs", "closedAt", "timestamptz")}
  ${j("createdAt")} timestamptz not null default now(),
  ${j("updatedAt")} timestamptz not null default now()
);
create index if not exists jobs_tenant_status_idx on ${t("jobs")} (${j("tenant")}, ${j("status")});${addExtraColumns(t("jobs"), extras)}
${lockModuleTable(ctx, "jobs", { read: true })}
${renderPolicy(makePolicy({ table: t("jobs"), name: "jobs_read", command: "select", roles: ["authenticated"], using: ctx.scope.check(j("tenant"), read) }), { drop: true, target: t("jobs") })}

create table if not exists ${t("applications")} (
  ${a("id")} uuid primary key default gen_random_uuid(),
  ${a("tenant")} ${ctx.idType} not null,
  ${a("job")} uuid not null references ${t("jobs")} (${j("id")}) on delete cascade,${fixedCandidate ? "" : `\n  ${a("candidateType")} text not null,`}
  ${a("candidateId")} ${candidateIdType} not null,${column("applications", "source", "text")}${column("applications", "owner", "uuid")}${column("applications", "pipeline", "uuid")}
  ${a("stage")} uuid,${column("applications", "stageEnteredAt", "timestamptz")}
  ${a("state")} text not null default 'active' check (${a("state")} in ('active', 'hired', 'rejected', 'withdrawn')),${column("applications", "rejectionReason", "text")}${column("applications", "hiredAt", "timestamptz")}
  ${a("rank")} text collate "C" not null default 'V',
  ${a("createdAt")} timestamptz not null default now(),
  ${a("updatedAt")} timestamptz not null default now(),
  unique (${a("job")}, ${fixedCandidate ? "" : `${a("candidateType")}, `}${a("candidateId")})
);
create index if not exists ${ctx.naming.rename("applications_board_idx")} on ${t("applications")} (${pipelined ? a("pipeline") : a("job")}, ${a("stage")}, ${a("rank")});
create index if not exists ${ctx.naming.rename("applications_candidate_idx")} on ${t("applications")} (${fixedCandidate ? "" : `${a("candidateType")}, `}${a("candidateId")});
${lockModuleTable(ctx, "applications", { read: true })}
${renderPolicy(makePolicy({ table: t("applications"), name: ctx.naming.rename("applications_read"), command: "select", roles: ["authenticated"], using: ctx.scope.check(a("tenant"), read) }), { drop: true, target: t("applications") })}

create table if not exists ${t("scorecards")} (
  ${s("id")} uuid primary key default gen_random_uuid(),
  ${s("tenant")} ${ctx.idType} not null,
  ${s("application")} uuid not null references ${t("applications")} (${a("id")}) on delete cascade,${column("scorecards", "stage", "uuid")}
  ${s("reviewer")} uuid not null,
  ${s("rating")} smallint not null check (${s("rating")} between 1 and 4),${ctx.has("scorecards", "recommendation") ? `\n  ${s("recommendation")} text not null check (${s("recommendation")} in ('strong_no', 'no', 'yes', 'strong_yes')),` : ""}${column("scorecards", "notes", "text")}
  ${s("submittedAt")} timestamptz not null default now(),
  ${perApplication ? `unique (${s("application")}, ${s("reviewer")})` : `unique nulls not distinct (${s("application")}, ${s("stage")}, ${s("reviewer")})`}
);${perApplication ? appUniqueIndex(ctx, "scorecards", ["application", "reviewer"]) : appUniqueIndex(ctx, "scorecards", ["application", "stage", "reviewer"]).replace(/;$/, " nulls not distinct;")}
create index if not exists ${ctx.naming.rename("application_scorecards_reviewer_idx")} on ${t("scorecards")} (${s("reviewer")});
${lockModuleTable(ctx, "scorecards", { read: true })}
${renderPolicy(makePolicy({ table: t("scorecards"), name: ctx.naming.rename("application_scorecards_read"), command: "select", roles: ["authenticated"], using: ctx.scope.check(s("tenant"), read) }), { drop: true, target: t("scorecards") })}
${scoreRows ? scoresTable(ctx, read) : ""}
create table if not exists ${t("interviews")} (
  ${v("id")} uuid primary key default gen_random_uuid(),
  ${v("tenant")} ${ctx.idType} not null,
  ${v("application")} uuid not null references ${t("applications")} (${a("id")}) on delete cascade,${column("interviews", "kind", "text")}
  ${v("startsAt")} timestamptz not null,
  ${v("endsAt")} timestamptz not null,${column("interviews", "location", "text")}${column("interviews", "interviewers", "uuid[] not null default '{}'")}${column("interviews", "createdBy", "uuid")}
  ${v("createdAt")} timestamptz not null default now(),
  check (${v("endsAt")} > ${v("startsAt")})
);
create index if not exists ${ctx.naming.rename("interviews_application_idx")} on ${t("interviews")} (${v("application")}, ${v("startsAt")});
${lockModuleTable(ctx, "interviews", { read: true })}${interviewerRows ? interviewersTable(ctx, read) : ""}
${renderPolicy(
  makePolicy({
    table: t("interviews"),
    name: ctx.naming.rename("interviews_read"),
    command: "select",
    roles: ["authenticated"],
    using: `${ctx.scope.check(v("tenant"), read)}${[
      ...(ctx.has("interviews", "interviewers")
        ? [`(select auth.uid()) = any (${v("interviewers")})`]
        : []),
      ...(interviewerRows
        ? [
            `exists (select 1 from ${t("interviewers")} z where z.${iv("interview")} = ${t("interviews")}.${v("id")} and z.${iv("user")} = (select auth.uid()))`,
          ]
        : []),
    ]
      .map((check) => ` or ${check}`)
      .join("")}`,
  }),
  { drop: true, target: t("interviews") },
)}
`
    : "";

  return `${schemaPreamble(ctx)}
-- Hiring: jobs, applications on a pipeline per job, scorecards per stage,
-- interviews, and a hire event the app turns into an employee.
${tables}
-- A rejected, withdrawn or hired application records its event and its
-- time; reopening clears them.
create or replace function better_supabase.${ctx.naming.rename("bsb_application_guard")}()
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
${ctx.has("applications", "hiredAt") ? `  new.${a("hiredAt")} := case when ${ctx.is("applications", "state", `new.${a("state")}`, ["hired"])} then now() end;\n` : ""}${
    ctx.has("applications", "rejectionReason")
      ? `  if ${ctx.is("applications", "state", `new.${a("state")}`, ["rejected"], true)} then
    new.${a("rejectionReason")} := null;
  end if;\n`
      : ""
  }  case ${ctx.label("applications", "state", `new.${a("state")}`)}
    when 'hired' then ${record("application.hired", "new")}
    when 'rejected' then ${record("application.rejected", "new", `, 'reason', ${or("applications", "new", "rejectionReason")}`)}
    when 'withdrawn' then ${record("application.retracted", "new")}
    else null;
  end case;
  new.${a("updatedAt")} := now();
  return new;
end;
$$;
${triggerGrant(`better_supabase.${ctx.naming.rename("bsb_application_guard")}()`)}
drop trigger if exists ${ctx.naming.rename("bsb_application_guard")} on ${t("applications")};
create trigger ${ctx.naming.rename("bsb_application_guard")} before update of ${a("state")} on ${t("applications")}
for each row execute function better_supabase.${ctx.naming.rename("bsb_application_guard")}();
${stages === undefined ? "" : stageTriggers(ctx, stages)}
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
  if not (${service} or ${jobAccess}) then
    ${fail("HIRING_FORBIDDEN", "not allowed to manage jobs")}
  end if;
  if save_job.job is not null then
    select * into v_job from ${t("jobs")} x where x.${j("id")} = save_job.job and x.${j("tenant")} = save_job.tenant;
    if v_job.${j("id")} is null then
      ${fail("HIRING_JOB_NOT_FOUND", "job not found", "P0002")}
    end if;
    v_was := v_job.${j("status")};
  end if;${managerCheck(ctx, managerEmployee)}${JOB_ATTRS.map(([logical, key, thing]) => refuse("jobs", logical, `save_job.attrs ->> '${key}'`, `HIRING_JOB_${thing.toUpperCase().replaceAll(" ", "_")}_UNSUPPORTED`, `this jobs table has no ${thing} column`)).join("")}
  begin
    if save_job.job is null then
      insert into ${t("jobs")} (${j("tenant")}, ${j("title")}${also("jobs", "team")}${also("jobs", "location")}${also("jobs", "employmentType")}${also("jobs", "description")}${also("jobs", "hiringManager")}, ${j("status")}${requiredJobColumns.columns})
      values (${lines(
        "        ",
        [
          "save_job.tenant",
          "save_job.attrs ->> 'title'",
          present("jobs", "team", "(save_job.attrs ->> 'teamId')::uuid"),
          present("jobs", "location", "save_job.attrs ->> 'location'"),
        ],
        [
          present(
            "jobs",
            "employmentType",
            ctx.cast(
              "jobs",
              "employmentType",
              "save_job.attrs ->> 'employmentType'",
            ),
          ),
          present("jobs", "description", "save_job.attrs ->> 'description'"),
          present("jobs", "hiringManager", managerValue),
        ],
        [
          ctx.cast(
            "jobs",
            "status",
            "coalesce(save_job.attrs ->> 'status', 'draft')",
          ),
        ],
      )}${requiredJobColumns.values})
      returning * into v_job;
    else
      update ${t("jobs")} x set
        ${j("title")} = coalesce(save_job.attrs ->> 'title', x.${j("title")}),${keep("team", "teamId", "(save_job.attrs ->> 'teamId')::uuid")}${keep("location", "location", "save_job.attrs ->> 'location'")}${keep("employmentType", "employmentType", ctx.cast("jobs", "employmentType", "save_job.attrs ->> 'employmentType'"))}${keep("description", "description", "save_job.attrs ->> 'description'")}${keep("hiringManager", "hiringManagerId", managerValue)}
        ${j("status")} = coalesce(${ctx.cast("jobs", "status", "save_job.attrs ->> 'status'")}, x.${j("status")}),
        ${j("updatedAt")} = now()
      where x.${j("id")} = save_job.job
      returning * into v_job;
    end if;
  exception when check_violation or not_null_violation or invalid_text_representation then
    ${fail("HIRING_JOB_INVALID", "a job needs a title and a status of draft, open or closed", "22023")}
  end;${writeExtraColumns(t("jobs"), extras, "save_job.attrs -> 'fields'", `x.${j("id")} = v_job.${j("id")}`, "v_job")}
  if ${asText(ctx, "jobs", `v_job.${j("status")}`)} is distinct from v_was then
    if ${ctx.is("jobs", "status", `v_job.${j("status")}`, ["open"])} then${stamp(
      [
        ctx.has("jobs", "openedAt")
          ? `${j("openedAt")} = coalesce(x.${j("openedAt")}, now())`
          : undefined,
        ctx.has("jobs", "closedAt") ? `${j("closedAt")} = null` : undefined,
      ],
    )}
      ${jobRecord("job.opened")}
    elsif ${ctx.is("jobs", "status", `v_job.${j("status")}`, ["closed"])} then${stamp(
      [ctx.has("jobs", "closedAt") ? `${j("closedAt")} = now()` : undefined],
    )}
      ${jobRecord("job.closed")}
    end if;
  end if;
  return ${withExtraFields(ctx.rowJson("jobs", "v_job"), "v_job", extras)};
end;
$$;
${userGrant(`${fn("save_job")}(${ctx.idType}, uuid, jsonb)`)}

-- An application of a candidate (a record in config.subjects, a person by
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
  if v_job.${j("id")} is null or not (${service} or ${ctx.scope.can(`v_job.${j("tenant")}`, createKey)}) then
    ${fail("HIRING_JOB_NOT_FOUND", "no such job you can add applications to", "P0002")}
  end if;
  if ${ctx.is("jobs", "status", `v_job.${j("status")}`, ["open"], true)} then
    ${fail("HIRING_JOB_NOT_OPEN", "the job isn't open", "55000")}
  end if;${
    fixedCandidate
      ? `
  if v_type <> ${sqlString(candidate)} then
    ${fail("HIRING_CANDIDATE_TYPE_UNSUPPORTED", `applications take candidates of type ${candidate} only`, "22023")}
  end if;`
      : ""
  }
  if v_id is null or not ${subjectInTenant(ctx, "v_type", "v_id", `v_job.${j("tenant")}`)} then
    ${fail("HIRING_CANDIDATE_FORBIDDEN", "the candidate is unknown or not readable in this organization", "42501")}
  end if;
  select * into v_row from ${t("applications")} x
  where x.${a("job")} = v_job.${j("id")}${fixedCandidate ? "" : ` and x.${a("candidateType")} = v_type`} and x.${a("candidateId")} = ${candidateValue("v_id")};
  if v_row.${a("id")} is not null then
    return ${applicationJson("v_row")};
  end if;${refuse("applications", "source", "nullif(trim(apply_to_job.source), '')", "HIRING_SOURCE_UNSUPPORTED", "this applications table has no source column")}${refuse("applications", "owner", "apply_to_job.owner", "HIRING_OWNER_UNSUPPORTED", "this applications table has no owner column")}
  insert into ${t("applications")} (${a("tenant")}, ${a("job")}, ${fixedCandidate ? "" : `${a("candidateType")}, `}${a("candidateId")}${also("applications", "source")}${also("applications", "owner")})
  values (v_job.${j("tenant")}, v_job.${j("id")}, ${fixedCandidate ? "" : "v_type, "}${candidateValue("v_id")}${alsoValue("applications", "source", ctx.cast("applications", "source", "nullif(trim(apply_to_job.source), '')"))}${alsoValue("applications", "owner", "coalesce(apply_to_job.owner, auth.uid())")})
  returning * into v_row;
  ${record("application.created", "v_row")}
  return ${applicationJson("v_row")};
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
  v_stage ${stages === undefined ? "uuid" : `${stages.table}.${stages.id}%type`};
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
${
  ctx.has("applications", "rejectionReason")
    ? `  update ${t("applications")} x set ${a("rejectionReason")} = nullif(trim(close_application.reason), '') where x.${a("id")} = v_row.${a("id")};`
    : refuse(
        "applications",
        "rejectionReason",
        "nullif(trim(close_application.reason), '')",
        "HIRING_REASON_UNSUPPORTED",
        "this applications table has no rejection reason column",
      ).slice(1)
}
  case close_application.outcome
    when 'hired' then ${pipelined ? moveTo("success", "hired") : closeInStages(ctx, stages, "hired")}
    when 'rejected' then ${pipelined ? moveTo("failure", "rejected") : closeInStages(ctx, stages, "rejected")}
    else ${pipelined ? moveTo("failure", "withdrawn") : closeInStages(ctx, stages, "withdrawn")}
  end case;
  if close_application.outcome = 'hired' then
    ${ctx.hook("after_application_hire", [["uuid", `v_row.${a("id")}`]])}
  end if;
  return (select ${applicationJson("x")} from ${t("applications")} x where x.${a("id")} = v_row.${a("id")});
end;
$$;
${userGrant(`${fn("close_application")}(uuid, text, text)`)}

-- The caller's scorecard on an application at its current stage: a rating
-- from 1 to 4 and a recommendation. Submitting again replaces it.
${scoreRows ? `drop function if exists ${fn("submit_scorecard")}(uuid, integer, text, text);\n` : ""}create or replace function ${fn("submit_scorecard")}(application uuid, rating integer, recommendation text, notes text${scoreRows ? ", scores jsonb default null" : ""})
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
  if v_row.${a("id")} is null or not ${reviewable(interviewerOf("y", "auth.uid()"), `(${service} or ${ctx.scope.can(`v_row.${a("tenant")}`, scoreKey)})`, `${t("interviews")} y where y.${v("application")} = v_row.${a("id")}`)} then
    ${fail("HIRING_APPLICATION_NOT_FOUND", "no such application you can review", "P0002")}
  end if;${refuse("scorecards", "notes", "submit_scorecard.notes", "HIRING_NOTES_UNSUPPORTED", "this scorecards table has no notes column")}${refuse("scorecards", "recommendation", "submit_scorecard.recommendation", "HIRING_RECOMMENDATION_UNSUPPORTED", "this scorecards table has no recommendation column")}${
    ctx.appOwned.includes("scorecards")
      ? ctx.has("scorecards", "recommendation")
        ? `
  if submit_scorecard.rating is null or submit_scorecard.rating not between 1 and 4
    or submit_scorecard.recommendation is null or submit_scorecard.recommendation not in ('strong_no', 'no', 'yes', 'strong_yes') then
    ${fail("HIRING_SCORECARD_INVALID", "a scorecard needs a rating from 1 to 4 and a recommendation", "22023")}
  end if;`
        : `
  if submit_scorecard.rating is null or submit_scorecard.rating not between 1 and 4 then
    ${fail("HIRING_SCORECARD_INVALID", "a scorecard needs a rating from 1 to 4", "22023")}
  end if;`
      : ""
  }
  begin
    insert into ${t("scorecards")} (${s("tenant")}, ${s("application")}${also("scorecards", "stage")}, ${s("reviewer")}, ${s("rating")}${also("scorecards", "recommendation")}${also("scorecards", "notes")})
    values (v_row.${a("tenant")}, v_row.${a("id")}${alsoValue("scorecards", "stage", `v_row.${a("stage")}`)}, auth.uid(), submit_scorecard.rating${ctx.has("scorecards", "recommendation") ? `, ${ctx.cast("scorecards", "recommendation", "submit_scorecard.recommendation")}` : ""}${alsoValue("scorecards", "notes", "submit_scorecard.notes")})
    on conflict (${perApplication ? `${s("application")}, ${s("reviewer")}` : `${s("application")}, ${s("stage")}, ${s("reviewer")}`}) do update set
      ${s("rating")} = excluded.${s("rating")}${ctx.has("scorecards", "recommendation") ? `, ${s("recommendation")} = excluded.${s("recommendation")}` : ""},
      ${perApplication && ctx.has("scorecards", "stage") ? `${s("stage")} = excluded.${s("stage")}, ` : ""}${ctx.has("scorecards", "notes") ? `${s("notes")} = excluded.${s("notes")}, ` : ""}${s("submittedAt")} = now()
    returning * into v_card;
  exception when check_violation or not_null_violation then
    ${fail("HIRING_SCORECARD_INVALID", "a scorecard needs a rating from 1 to 4 and a recommendation", "22023")}
  end;${scoreRows ? scoresWrite(ctx) : ""}
  ${record("scorecard.submitted", "v_row", `, 'reviewerId', v_card.${s("reviewer")}, 'recommendation', ${or("scorecards", "v_card", "recommendation")}`)}
  return ${scorecardJson("v_card")};
end;
$$;
${userGrant(`${fn("submit_scorecard")}(uuid, integer, text, text${scoreRows ? ", jsonb" : ""})`)}

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
  end if;${
    ctx.has("interviews", "interviewers") || interviewerRows
      ? ""
      : `
  if coalesce(cardinality(schedule_interview.interviewers), 0) > 0 then
    ${fail("HIRING_INTERVIEWERS_UNSUPPORTED", "this interviews table keeps no interviewers", "22023")}
  end if;`
  }${refuse("interviews", "kind", "schedule_interview.kind", "HIRING_INTERVIEW_KIND_UNSUPPORTED", "this interviews table has no kind column")}${refuse("interviews", "location", "schedule_interview.location", "HIRING_INTERVIEW_LOCATION_UNSUPPORTED", "this interviews table has no location column")}${
    ctx.appOwned.includes("interviews")
      ? `
  if not (schedule_interview.ends_at > schedule_interview.starts_at) then
    ${fail("HIRING_INTERVIEW_INVALID", "an interview needs a start before its end", "22023")}
  end if;`
      : ""
  }
  begin
    insert into ${t("interviews")} (${v("tenant")}, ${v("application")}${also("interviews", "kind")}, ${v("startsAt")}, ${v("endsAt")}${also("interviews", "location")}${also("interviews", "interviewers")}${also("interviews", "createdBy")})
    values (${lines(
      "      ",
      [
        `v_row.${a("tenant")}`,
        `v_row.${a("id")}`,
        present(
          "interviews",
          "kind",
          ctx.cast("interviews", "kind", "schedule_interview.kind"),
        ),
        "schedule_interview.starts_at",
        "schedule_interview.ends_at",
      ],
      [
        present("interviews", "location", "schedule_interview.location"),
        present(
          "interviews",
          "interviewers",
          "coalesce(schedule_interview.interviewers, '{}')",
        ),
        present("interviews", "createdBy", "auth.uid()"),
      ],
    )})
    returning * into v_interview;
  exception when check_violation or not_null_violation then
    ${fail("HIRING_INTERVIEW_INVALID", "an interview needs a start before its end", "22023")}
  end;${
    interviewerRows
      ? `
  insert into ${t("interviewers")} (${ctx.has("interviewers", "tenant") ? `${iv("tenant")}, ` : ""}${iv("interview")}, ${iv("user")})
  select distinct ${ctx.has("interviewers", "tenant") ? `v_row.${a("tenant")}, ` : ""}v_interview.${v("id")}, u
  from unnest(coalesce(schedule_interview.interviewers, '{}')) u;`
      : ""
  }
  ${record("interview.scheduled", "v_row", `, 'interviewId', v_interview.${v("id")}, 'startsAt', v_interview.${v("startsAt")}`)}
  return ${interviewJson("v_interview")};
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
  select ${applicationJson("x")} || jsonb_build_object(
    'scorecards', coalesce((select jsonb_agg(${scorecardJson("c")} order by c.${s("submittedAt")}) from ${t("scorecards")} c where c.${s("application")} = x.${a("id")}), '[]'::jsonb),
    'interviews', coalesce((select jsonb_agg(${interviewJson("i")} order by i.${v("startsAt")}) from ${t("interviews")} i where i.${v("application")} = x.${a("id")}), '[]'::jsonb),
    'averageRating', (select round(avg(c.${s("rating")}), 2) from ${t("scorecards")} c where c.${s("application")} = x.${a("id")}))
  from ${t("applications")} x where x.${a("id")} = application_detail.application
$$;
${userGrant(`${fn("application_detail")}(uuid)`)}
`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
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
      args: [
        "uuid",
        "integer",
        "text",
        "text",
        ...(optIn(ctx, "scorecardScores") ? ["jsonb"] : []),
      ],
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

/** The application state each stage category writes. */
const APPLICATION_STATES: Readonly<Record<string, string>> = {
  active: "active",
  hired: "hired",
  rejected: "rejected",
  withdrawn: "withdrawn",
};

/** The stage categories and stages of an application's first pipeline. */
const APPLICATION_PIPELINE: Readonly<Record<string, unknown>> = {
  categories: {
    active: "open",
    hired: "success",
    rejected: "failure",
    withdrawn: "failure",
  },
  stages: [
    { key: "applied", name: "Applied", category: "active" },
    { key: "screening", name: "Screening", category: "active" },
    { key: "interview", name: "Interview", category: "active" },
    { key: "offer", name: "Offer", category: "active" },
    { key: "hired", name: "Hired", category: "hired" },
    { key: "rejected", name: "Rejected", category: "rejected" },
    { key: "withdrawn", name: "Withdrawn", category: "withdrawn" },
  ],
};

/** How applications run on pipelines, in the columns of `own`'s table. */
function applicationPipeline(
  own: BlockSqlContext,
): Readonly<Record<string, unknown>> {
  const column = (logical: string): string | undefined =>
    own.has("applications", logical)
      ? own.colName("applications", logical)
      : undefined;

  return {
    stage: column("stage"),
    pipeline: column("pipeline"),
    enteredAt: column("stageEnteredAt"),
    owner: column("owner"),
    scope: column("job"),
    ...APPLICATION_PIPELINE,
    status: {
      column: column("state"),
      values: Object.fromEntries(
        Object.entries(APPLICATION_STATES).flatMap(([category, label]) => {
          const [value] = own.appValues("applications", "state", label);

          return value === undefined ? [] : [[category, value]];
        }),
      ),
    },
  };
}

const CONTRIBUTES: BlockContributes = {
  pipelines: (own) => {
    if (jobStages(own) !== undefined || !own.has("applications", "pipeline")) {
      return [];
    }

    const { schema, name } = own.tableName("applications");

    return [
      {
        type: own.resolved.entityNaming.rename("application"),
        table: `${schema}.${name}`,
        tenant: own.colName("applications", "tenant"),
        entry: applicationPipeline(own),
      },
    ];
  },
};

export const HIRING: BlockSqlDefinition = {
  contributes: CONTRIBUTES,
  name: "hiring",
  scopes: ["tenant"],
  title: "Hiring",
  description:
    "Jobs and applications on a pipeline per job, candidates from config.subjects, scorecards per stage, interviews, and hire, reject and withdraw events for the app to act on.",
  requires: ["memberships", "permissions", "subjects", "pipelines"],
  // The pipelines module binds the applications table, so the table comes first.
  before: "pipelines",
  integrates: ["outbox", "automations", "employees"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 2,
  names: NAMES,
  contract,
  build,
  data: (ctx) =>
    shippedAutomation(ctx, APPLICATION_TO_EMPLOYEE, {
      module: "employees",
      singular: "employee",
    }),
};
