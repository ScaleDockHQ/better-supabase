import type { WorkflowsEvents } from "../../blocks/workflows/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { NOTHING } from "../context.ts";
import {
  schemaPreamble,
  SERVICE_CALLER,
  serviceGrant,
  pageSize,
  fail,
  ensureCheck,
} from "../shared.ts";
import { appUniqueIndex, asText, lockModuleTable } from "./over-app.ts";
import { moduleOperations } from "./permissions-model.ts";
import { recordWorkflowRunSql } from "./workflows-record.ts";

const EVENTS: BlockSqlEvents<WorkflowsEvents> = {
  "workflow_run.completed": {
    subject: "workflow-runs",
    payload: [
      "runId",
      "organizationId",
      "engine",
      "externalId",
      "definition",
      "status",
      "error",
      "subjectType",
      "subjectId",
    ],
    retries: true,
  },
  "workflow_run.failed": {
    subject: "workflow-runs",
    payload: [
      "runId",
      "organizationId",
      "engine",
      "externalId",
      "definition",
      "status",
      "error",
      "subjectType",
      "subjectId",
    ],
    retries: true,
  },
  "workflow_run.cancelled": {
    subject: "workflow-runs",
    payload: [
      "runId",
      "organizationId",
      "engine",
      "externalId",
      "definition",
      "status",
      "error",
      "subjectType",
      "subjectId",
    ],
    retries: true,
  },
};

const NAMES: BlockSqlNames = {
  events: EVENTS,
  tables: {
    runs: {
      name: "workflow_runs",
      app: {},
      lifecycle: { user: "actor", tenant: "tenant" },
      columns: {
        id: "id",
        engine: "engine",
        externalId: "external_id",
        definition: "definition",
        tenant: "tenant_id",
        actor: "actor_id",
        status: "status",
        attributes: "attributes",
        error: "error",
        createdAt: "created_at",
        updatedAt: "updated_at",
        startedAt: "started_at",
        completedAt: "completed_at",
        cancelRequestedAt: "cancel_requested_at",
        subjectType: "subject_type",
        subjectId: "subject_id",
        principalKind: "principal_kind",
        principalId: "principal_id",
        mode: "mode",
        triggerNode: "trigger_node",
      },
      optional: ["subjectType", "subjectId", "mode", "triggerNode"],
      typed: ["status", "mode"],
    },
    schedules: {
      name: "workflow_schedules",
      app: {},
      lifecycle: { user: "createdBy", tenant: "tenant" },
      columns: {
        id: "id",
        tenant: "tenant_id",
        name: "name",
        workflow: "workflow",
        input: "input",
        cron: "cron",
        timezone: "timezone",
        nextRunAt: "next_run_at",
        lastRunAt: "last_run_at",
        lockedUntil: "locked_until",
        paused: "paused",
        createdBy: "created_by",
        createdAt: "created_at",
      },
      optional: ["lastRunAt"],
    },
    semaphores: {
      name: "workflow_semaphores",
      app: {},
      columns: {
        key: "key",
        holder: "holder",
        acquiredAt: "acquired_at",
        expiresAt: "expires_at",
      },
    },
    startRequests: {
      name: "workflow_start_requests",
      app: {},
      lifecycle: { user: "actor", tenant: "tenant" },
      columns: {
        id: "id",
        key: "key",
        workflow: "workflow",
        input: "input",
        tenant: "tenant_id",
        actor: "actor_id",
        concurrency: "concurrency",
        status: "status",
        notBefore: "not_before",
        claimedUntil: "claimed_until",
        runId: "run_id",
        createdAt: "created_at",
        startedAt: "started_at",
        subjectType: "subject_type",
        subjectId: "subject_id",
      },
      optional: ["subjectType", "subjectId"],
      typed: ["status"],
    },
  },
};

const WORKFLOW_RUN_STATUSES = [
  "queued",
  "running",
  "waiting",
  "completed",
  "failed",
  "cancelled",
] as const;

/** Who a run's steps act as: `principal_kind` on `workflow_runs`. */
const PRINCIPAL_KINDS = [
  "user",
  "service_principal",
  "system",
  "external",
] as const;

const TERMINAL = "('completed', 'failed', 'cancelled')";

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const id = ctx.idType;
  const fn = (name: string): string => ctx.fn(name);
  const r = ctx.table("runs");
  const s = ctx.table("schedules");
  const m = ctx.table("semaphores");
  const q = ctx.table("startRequests");
  const cr = (column: string): string => ctx.col("runs", column);
  const cs = (column: string): string => ctx.col("schedules", column);
  const cm = (column: string): string => ctx.col("semaphores", column);
  const cq = (column: string): string => ctx.col("startRequests", column);
  const permissions = moduleOperations("workflows");

  const can = (tenant: string, action: "read" | "run" | "admin"): string =>
    ctx.can("tenant", tenant, ctx.permission(action, permissions[action]));

  const callable = (signature: string): string =>
    `revoke execute on function ${signature} from public, anon;
grant execute on function ${signature} to authenticated, service_role;`;

  const linked = ctx.has("runs", "subjectType") && ctx.has("runs", "subjectId");
  const moded = ctx.has("runs", "mode");
  const nodded = ctx.has("runs", "triggerNode");
  const app = ctx.appOwned.includes("runs");

  const queued =
    ctx.has("startRequests", "subjectType") &&
    ctx.has("startRequests", "subjectId");

  const lastRun = ctx.has("schedules", "lastRunAt");
  const ownSchedules = ctx.owns("schedules");

  // A parameter of create_workflow_schedule. Over the app's table its upsert
  // names the key columns, which a same-named parameter would shadow.
  const arg = (name: string): string =>
    ownSchedules ? name : `create_workflow_schedule.${name}`;

  // A subject column of row, or null without the subject columns.
  const subjectOf = (row: string, logical: string): string =>
    linked ? `${row}.${cr(logical)}` : "null";

  const runJson = (alias: string): string => `jsonb_build_object(
    'id', ${alias}.${cr("id")},
    'engine', ${alias}.${cr("engine")},
    'externalId', ${alias}.${cr("externalId")},
    'definition', ${alias}.${cr("definition")},
    'tenant', ${alias}.${cr("tenant")},
    'actor', ${alias}.${cr("actor")},
    'status', ${alias}.${cr("status")},
    'attributes', ${alias}.${cr("attributes")},
    'error', ${alias}.${cr("error")},
    'createdAt', ${alias}.${cr("createdAt")},
    'updatedAt', ${alias}.${cr("updatedAt")},
    'startedAt', ${alias}.${cr("startedAt")},
    'completedAt', ${alias}.${cr("completedAt")},
    'cancelRequestedAt', ${alias}.${cr("cancelRequestedAt")},
    'subjectType', ${subjectOf(alias, "subjectType")},
    'subjectId', ${subjectOf(alias, "subjectId")},
    'principalKind', ${alias}.${cr("principalKind")},
    'principalId', ${alias}.${cr("principalId")},
    'mode', ${moded ? `${alias}.${cr("mode")}` : "'live'"},
    'triggerNode', ${nodded ? `${alias}.${cr("triggerNode")}` : `${alias}.${cr("attributes")} ->> 'bsb.trigger_node'`}
  )`;

  const scheduleJson = (alias: string): string => `jsonb_build_object(
    'id', ${alias}.${cs("id")},
    'tenant', ${alias}.${cs("tenant")},
    'name', ${alias}.${cs("name")},
    'workflow', ${alias}.${cs("workflow")},
    'input', ${alias}.${cs("input")},
    'cron', ${alias}.${cs("cron")},
    'timezone', ${alias}.${cs("timezone")},
    'nextRunAt', ${alias}.${cs("nextRunAt")},
    'lastRunAt', ${lastRun ? `${alias}.${cs("lastRunAt")}` : "null::timestamptz"},
    'paused', ${alias}.${cs("paused")},
    'createdBy', ${alias}.${cs("createdBy")},
    'createdAt', ${alias}.${cs("createdAt")}
  )`;

  const emitTerminal = (status: string): string =>
    ctx.record({
      type: `workflow_run.${status}`,
      payload: `jsonb_build_object('runId', new.${cr("id")}, 'organizationId', new.${cr("tenant")}::text, 'engine', new.${cr("engine")}, 'externalId', new.${cr("externalId")}, 'definition', new.${cr("definition")}, 'status', new.${cr("status")}, 'error', new.${cr("error")}, 'subjectType', ${subjectOf("new", "subjectType")}, 'subjectId', ${subjectOf("new", "subjectId")})`,
      subject: `'workflow-runs/' || new.${cr("id")}`,
      tenant: `new.${cr("tenant")}`,
      key: `'workflow_run.${status}:' || new.${cr("id")}`,
      audit: false,
    });

  const terminalEvents = ["completed", "failed", "cancelled"]
    .map((status) => {
      const emit = emitTerminal(status);

      return emit === NOTHING
        ? ""
        : `\n    when ${sqlString(status)} then\n      ${emit}`;
    })
    .join("");

  const statusTrigger = ctx.trigger("workflow_runs_status");
  const receive = ctx.trigger("workflow_runs_receive");
  // The tenant topic id is the tenant cast to text; the run topic id is the run's uuid.
  const tenantTopic = `'workflow-runs:' || new.${cr("tenant")}::text`;

  return `${schemaPreamble(ctx)}
-- Workflow runs of any engine, one row per run. Engines write them through
-- record_workflow_run (the Workflow SDK World mirrors its own runs); members
-- read them through RLS.
create table if not exists ${r} (
  ${cr("id")} uuid primary key default gen_random_uuid(),
  ${cr("engine")} text not null check (length(${cr("engine")}) between 1 and 100),
  ${cr("externalId")} text not null check (length(${cr("externalId")}) between 1 and 200),
  ${cr("definition")} text not null check (length(${cr("definition")}) between 1 and 200),
  ${cr("tenant")} ${id},
  ${cr("actor")} uuid references auth.users (id) on delete set null,
  ${cr("status")} text not null default 'queued' check (${cr("status")} in (${WORKFLOW_RUN_STATUSES.map(sqlString).join(", ")})),
  ${cr("attributes")} jsonb not null default '{}'::jsonb,
  ${cr("error")} text,
  ${cr("createdAt")} timestamptz not null default now(),
  ${cr("updatedAt")} timestamptz not null default now(),
  ${cr("startedAt")} timestamptz,
  ${cr("completedAt")} timestamptz,
  ${cr("cancelRequestedAt")} timestamptz,
  constraint workflow_runs_engine_external_key unique (${cr("engine")}, ${cr("externalId")})
);${appUniqueIndex(ctx, "runs", ["engine", "externalId"])}
create index if not exists workflow_runs_tenant_idx on ${r} (${cr("tenant")}, ${cr("createdAt")} desc);
create index if not exists workflow_runs_actor_idx on ${r} (${cr("actor")}, ${cr("createdAt")} desc);
create index if not exists workflow_runs_status_idx on ${r} (${cr("status")}, ${cr("completedAt")});
-- The record a run belongs to (subject_type and subject_id, both or
-- neither), who its steps run as (principal_kind and principal_id), whether
-- it is a test run, and the trigger node it started from. Test runs write
-- no outbox events and fire no alerts.
${
  linked
    ? `alter table ${r} add column if not exists ${cr("subjectType")} text check (length(${cr("subjectType")}) between 1 and 100);
alter table ${r} add column if not exists ${cr("subjectId")} text check (length(${cr("subjectId")}) between 1 and 200);
`
    : ""
}alter table ${r} add column if not exists ${cr("principalKind")} text check (${cr("principalKind")} in (${PRINCIPAL_KINDS.map(sqlString).join(", ")}));
alter table ${r} add column if not exists ${cr("principalId")} text check (length(${cr("principalId")}) between 1 and 200);${moded ? `\nalter table ${r} add column if not exists ${cr("mode")} text not null default 'live' check (${cr("mode")} in ('live', 'test'));` : ""}${nodded ? `\nalter table ${r} add column if not exists ${cr("triggerNode")} text check (length(${cr("triggerNode")}) between 1 and 100);` : ""}${
    linked
      ? `${app ? "" : `\n${ensureCheck(r, "workflow_runs_subject_check", `(${cr("subjectType")} is null) = (${cr("subjectId")} is null)`)}`}
create index if not exists workflow_runs_subject_idx on ${r} (${cr("tenant")}, ${cr("subjectType")}, ${cr("subjectId")}, ${cr("createdAt")} desc) where ${cr("subjectType")} is not null;`
      : ""
  }
${lockModuleTable(ctx, "runs", { read: true })}
drop policy if exists workflow_runs_read on ${r};
create policy workflow_runs_read on ${r} for select to authenticated
  using (
    ${cr("actor")} = (select auth.uid())
    or ${ctx.scope.check(cr("tenant"), ctx.permission("read", permissions.read))}
  );

-- Recurring starts. The tick (createWorkflows().schedules.tick) claims due
-- rows, starts each run with the key schedule:<id>:<fire time> and moves
-- next_run_at on with the next cron time it computes.
create table if not exists ${s} (
  ${cs("id")} uuid primary key default gen_random_uuid(),
  ${cs("tenant")} ${id},
  ${cs("name")} text not null check (length(${cs("name")}) between 1 and 200),
  ${cs("workflow")} text not null check (length(${cs("workflow")}) between 1 and 200),
  ${cs("input")} jsonb not null default '[]'::jsonb,
  ${cs("cron")} text not null check (length(${cs("cron")}) between 1 and 200),
  ${cs("timezone")} text not null default 'UTC',
  ${cs("nextRunAt")} timestamptz not null,
${
  lastRun
    ? `  ${cs("lastRunAt")} timestamptz,
`
    : ""
}  ${cs("lockedUntil")} timestamptz,
  ${cs("paused")} boolean not null default false,
  ${cs("createdBy")} uuid references auth.users (id) on delete set null,
  ${cs("createdAt")} timestamptz not null default now(),
  constraint workflow_schedules_tenant_name_key unique nulls not distinct (${cs("tenant")}, ${cs("name")})
);${
    ownSchedules
      ? ""
      : `
create unique index if not exists ${sqlIdent(`${ctx.tableName("schedules").name}_${ctx.colName("schedules", "tenant")}_${ctx.colName("schedules", "name")}_key`.slice(0, 63))} on ${s} (${cs("tenant")}, ${cs("name")}) nulls not distinct;`
  }
create index if not exists workflow_schedules_due_idx on ${s} (${cs("nextRunAt")}) where not ${cs("paused")};
create index if not exists workflow_schedules_created_by_idx on ${s} (${cs("createdBy")});
${lockModuleTable(ctx, "schedules", { read: true })}
drop policy if exists workflow_schedules_read on ${s};
create policy workflow_schedules_read on ${s} for select to authenticated
  using (${ctx.scope.check(cs("tenant"), ctx.permission("read", permissions.read))});

-- Counting semaphores: at most limit holders per key, each until it releases
-- or its lease runs out.
create table if not exists ${m} (
  ${cm("key")} text not null check (length(${cm("key")}) between 1 and 200),
  ${cm("holder")} text not null check (length(${cm("holder")}) between 1 and 200),
  ${cm("acquiredAt")} timestamptz not null default now(),
  ${cm("expiresAt")} timestamptz not null,
  primary key (${cm("key")}, ${cm("holder")})
);
${lockModuleTable(ctx, "semaphores")}

-- Admission control for starts: a request waits here until its key has room
-- (concurrency), its debounce window passed, or is dropped while a run with
-- its key is active (singleton).
create table if not exists ${q} (
  ${cq("id")} uuid primary key default gen_random_uuid(),
  ${cq("key")} text not null check (length(${cq("key")}) between 1 and 200),
  ${cq("workflow")} text not null check (length(${cq("workflow")}) between 1 and 200),
  ${cq("input")} jsonb not null default '[]'::jsonb,
  ${cq("tenant")} ${id},
  ${cq("actor")} uuid references auth.users (id) on delete set null,
  ${cq("concurrency")} integer check (${cq("concurrency")} > 0),
  ${cq("status")} text not null default 'pending' check (${cq("status")} in ('pending', 'started', 'superseded', 'dropped')),
  ${cq("notBefore")} timestamptz not null default now(),
  ${cq("claimedUntil")} timestamptz,
  ${cq("runId")} text,
  ${cq("createdAt")} timestamptz not null default now(),
  ${cq("startedAt")} timestamptz
);
create index if not exists workflow_start_requests_key_idx on ${q} (${cq("key")}, ${cq("status")});
create index if not exists workflow_start_requests_due_idx on ${q} (${cq("notBefore")}) where ${cq("status")} = 'pending';
create index if not exists workflow_start_requests_actor_idx on ${q} (${cq("actor")});
${
  queued
    ? `alter table ${q} add column if not exists ${cq("subjectType")} text check (length(${cq("subjectType")}) between 1 and 100);
alter table ${q} add column if not exists ${cq("subjectId")} text check (length(${cq("subjectId")}) between 1 and 200);
${ctx.owns("startRequests") ? `${ensureCheck(q, "workflow_start_requests_subject_check", `(${cq("subjectType")} is null) = (${cq("subjectId")} is null)`)}\n` : ""}`
    : ""
}${lockModuleTable(ctx, "startRequests")}

-- Pings the run's topic and its tenant's topic on every status change, and
-- writes workflow_run.completed, .failed or .cancelled to the outbox (not
-- for test runs).
create or replace function ${fn("workflow_runs_changed")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and old.${cr("status")} = new.${cr("status")} then
    return null;
  end if;
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(jsonb_build_object('id', new.${cr("id")}, 'status', new.${cr("status")}), 'status', 'workflow-run:' || new.${cr("id")}::text, true);
    if new.${cr("tenant")} is not null then
      perform realtime.send(jsonb_build_object('id', new.${cr("id")}, 'status', new.${cr("status")}), 'status', ${tenantTopic}, true);
    end if;
  end if;${
    terminalEvents === ""
      ? ""
      : `${
          moded
            ? `
  if new.${cr("mode")} = 'test' then
    return null;
  end if;`
            : ""
        }
  case new.${cr("status")}${terminalEvents}
    else null;
  end case;`
  }
  return null;
end;
$$;
revoke execute on function ${fn("workflow_runs_changed")}() from public, anon, authenticated;
drop trigger if exists ${statusTrigger} on ${r};
create trigger ${statusTrigger} after insert or update of ${cr("status")} on ${r}
  for each row execute function ${fn("workflow_runs_changed")}();

${recordWorkflowRunSql(ctx)}

-- The runs the caller may read, newest first: max rows created before before.
-- subject_type and subject_id narrow to one record's runs; mode is live
-- (the default), test, or null for both.
drop function if exists ${fn("workflow_runs_list")}(${id}, text, text, integer, timestamptz);
create or replace function ${fn("workflow_runs_list")}(
  tenant ${id} default null,
  definition text default null,
  status text default null,
  max integer default 50,
  before timestamptz default null,
  subject_type text default null,
  subject_id text default null,
  mode text default 'live'
)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(${runJson("x")} order by x.${cr("createdAt")} desc), '[]'::jsonb)
  from (
    select * from ${r} y
    where (workflow_runs_list.tenant is null or y.${cr("tenant")} = workflow_runs_list.tenant)
      and (workflow_runs_list.definition is null or y.${cr("definition")} = workflow_runs_list.definition)
      and (workflow_runs_list.status is null or ${asText(ctx, "runs", `y.${cr("status")}`)} = workflow_runs_list.status)
      and (workflow_runs_list.before is null or y.${cr("createdAt")} < workflow_runs_list.before)
      and (workflow_runs_list.subject_type is null or ${linked ? `y.${cr("subjectType")} = workflow_runs_list.subject_type` : "false"})
      and (workflow_runs_list.subject_id is null or ${linked ? `y.${cr("subjectId")} = workflow_runs_list.subject_id` : "false"})
      and (workflow_runs_list.mode is null or ${moded ? asText(ctx, "runs", `y.${cr("mode")}`) : "'live'"} = workflow_runs_list.mode)
    order by y.${cr("createdAt")} desc
    limit ${pageSize("workflow_runs_list.max", 50, 500)}
  ) x;
$$;
${callable(`${fn("workflow_runs_list")}(${id}, text, text, integer, timestamptz, text, text, text)`)}

-- One run by its id or its engine's id, when the caller may read it.
create or replace function ${fn("workflow_run_get")}(run text)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select ${runJson("x")}
  from ${r} x
  where x.${cr("id")}::text = workflow_run_get.run or x.${cr("externalId")} = workflow_run_get.run
  order by x.${cr("id")}::text = workflow_run_get.run desc
  limit 1;
$$;
${callable(`${fn("workflow_run_get")}(text)`)}

-- Marks a run for cancellation and returns it, or null when the caller may
-- not cancel it: the service role, the actor, or workflow.admin in its
-- tenant. The engine does the cancelling.
create or replace function ${fn("request_workflow_cancel")}(run text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run ${r}%rowtype;
begin
  select * into v_run from ${r} x
  where (x.${cr("id")}::text = request_workflow_cancel.run or x.${cr("externalId")} = request_workflow_cancel.run)
  order by x.${cr("id")}::text = request_workflow_cancel.run desc
  limit 1
  for update;
  if not found then
    return null;
  end if;
  if not (${SERVICE_CALLER}
    or v_run.${cr("actor")} = (select auth.uid())
    or (v_run.${cr("tenant")} is not null and ${can(`v_run.${cr("tenant")}`, "admin")})) then
    ${fail("WORKFLOW_FORBIDDEN", "You may not cancel this run")}
  end if;
  if v_run.${cr("status")} in ${TERMINAL} then
    return ${runJson("v_run")};
  end if;
  update ${r} set ${cr("cancelRequestedAt")} = coalesce(${cr("cancelRequestedAt")}, now()), ${cr("updatedAt")} = now()
  where ${cr("id")} = v_run.${cr("id")}
  returning * into v_run;
  return ${runJson("v_run")};
end;
$$;
${callable(`${fn("request_workflow_cancel")}(text)`)}

-- Deletes finished runs older than older_than and old start requests, at
-- most batch of each per call.
create or replace function ${fn("purge_workflow_runs")}(older_than interval default '30 days', batch integer default 1000)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_runs integer;
begin
  with doomed as (
    select ${cr("id")} from ${r}
    where ${cr("status")} in ${TERMINAL}
      and ${ctx.expired("workflow_runs", { at: `coalesce(${cr("completedAt")}, ${cr("updatedAt")})`, tenant: cr("tenant"), fallback: "coalesce(older_than, interval '30 days')" })}
    limit greatest(coalesce(batch, 1000), 1)
  )
  delete from ${r} x using doomed where x.${cr("id")} = doomed.${cr("id")};
  get diagnostics v_runs = row_count;
  with doomed as (
    select ${cq("id")} from ${q}
    where ${cq("status")} <> 'pending'
      and ${cq("createdAt")} < now() - coalesce(older_than, interval '30 days')
    limit greatest(coalesce(batch, 1000), 1)
  )
  delete from ${q} x using doomed where x.${cq("id")} = doomed.${cq("id")};
  delete from ${m} where ${cm("expiresAt")} < now();
  return v_runs;
end;
$$;
${serviceGrant(`${fn("purge_workflow_runs")}(interval, integer)`)}

-- Creates a schedule, or replaces the one with the same tenant and name.
-- The service role, or workflow.admin in tenant. payload is { input }: the
-- workflow's arguments.
create or replace function ${fn("create_workflow_schedule")}(
  name text,
  workflow text,
  cron text,
  next_run timestamptz,
  payload jsonb default '{}'::jsonb,
  timezone text default 'UTC',
  tenant ${id} default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict ${ownSchedules ? "use_variable" : "use_column"}
declare
  v_row ${s}%rowtype;
begin
  if not (${SERVICE_CALLER} or (${arg("tenant")} is not null and ${can(arg("tenant"), "admin")})) then
    ${fail("WORKFLOW_FORBIDDEN", "You may not schedule workflows here")}
  end if;
  insert into ${s} as x (${cs("tenant")}, ${cs("name")}, ${cs("workflow")}, ${cs("input")}, ${cs("cron")}, ${cs("timezone")}, ${cs("nextRunAt")}, ${cs("createdBy")})
  values (${arg("tenant")}, ${arg("name")}, ${arg("workflow")}, coalesce(${arg("payload")} -> 'input', '[]'::jsonb), ${arg("cron")}, coalesce(${arg("timezone")}, 'UTC'), ${arg("next_run")}, (select auth.uid()))
  on conflict ${ownSchedules ? "on constraint workflow_schedules_tenant_name_key" : `(${cs("tenant")}, ${cs("name")})`} do update set
    ${cs("workflow")} = excluded.${cs("workflow")},
    ${cs("input")} = excluded.${cs("input")},
    ${cs("cron")} = excluded.${cs("cron")},
    ${cs("timezone")} = excluded.${cs("timezone")},
    ${cs("nextRunAt")} = excluded.${cs("nextRunAt")},
    ${cs("lockedUntil")} = null
  returning * into v_row;
  return ${scheduleJson("v_row")};
end;
$$;
${callable(`${fn("create_workflow_schedule")}(text, text, text, timestamptz, jsonb, text, ${id})`)}

-- The schedules the caller may read, by name.
create or replace function ${fn("workflow_schedules_list")}(tenant ${id} default null)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(${scheduleJson("x")} order by x.${cs("name")}), '[]'::jsonb)
  from ${s} x
  where workflow_schedules_list.tenant is null or x.${cs("tenant")} = workflow_schedules_list.tenant;
$$;
${callable(`${fn("workflow_schedules_list")}(${id})`)}

-- Pauses or resumes a schedule; false when there is none the caller manages.
create or replace function ${fn("pause_workflow_schedule")}(schedule uuid, paused boolean default true)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  update ${s} x set ${cs("paused")} = coalesce(paused, true)
  where x.${cs("id")} = schedule
    and (${SERVICE_CALLER} or (x.${cs("tenant")} is not null and ${can(`x.${cs("tenant")}`, "admin")}));
  return found;
end;
$$;
${callable(`${fn("pause_workflow_schedule")}(uuid, boolean)`)}

create or replace function ${fn("remove_workflow_schedule")}(schedule uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  delete from ${s} x
  where x.${cs("id")} = schedule
    and (${SERVICE_CALLER} or (x.${cs("tenant")} is not null and ${can(`x.${cs("tenant")}`, "admin")}));
  return found;
end;
$$;
${callable(`${fn("remove_workflow_schedule")}(uuid)`)}

-- Leases up to batch due schedules for lease seconds:
-- [{ id, tenant, name, workflow, input, cron, timezone, fireAt }].
create or replace function ${fn("claim_due_workflow_schedules")}(lease integer default 60, batch integer default 50)
returns jsonb
language sql
set search_path = ''
as $$
  with due as (
    select ${cs("id")} from ${s}
    where not ${cs("paused")}
      and ${cs("nextRunAt")} <= now()
      and (${cs("lockedUntil")} is null or ${cs("lockedUntil")} < now())
    order by ${cs("nextRunAt")}
    limit greatest(coalesce(batch, 50), 1)
    for update skip locked
  ),
  leased as (
    update ${s} x set ${cs("lockedUntil")} = now() + make_interval(secs => greatest(coalesce(lease, 60), 1))
    from due where x.${cs("id")} = due.${cs("id")}
    returning x.*
  )
  select coalesce(jsonb_agg(${scheduleJson("leased")} || jsonb_build_object('fireAt', leased.${cs("nextRunAt")}) order by leased.${cs("nextRunAt")}), '[]'::jsonb)
  from leased;
$$;
${serviceGrant(`${fn("claim_due_workflow_schedules")}(integer, integer)`)}

-- Records a fire and moves the schedule to next_run. false when another tick
-- already advanced it past fired.
create or replace function ${fn("advance_workflow_schedule")}(schedule uuid, fired timestamptz, next_run timestamptz)
returns boolean
language plpgsql
set search_path = ''
as $$
#variable_conflict use_variable
begin
  update ${s} x set ${lastRun ? `${cs("lastRunAt")} = fired, ` : ""}${cs("nextRunAt")} = next_run, ${cs("lockedUntil")} = null
  where x.${cs("id")} = schedule and x.${cs("nextRunAt")} = fired;
  return found;
end;
$$;
${serviceGrant(`${fn("advance_workflow_schedule")}(uuid, timestamptz, timestamptz)`)}

-- Takes one of max slots of key for holder until it releases or ttl passes.
-- true when holder holds a slot (again, for a holder that already held one).
create or replace function ${fn("acquire_workflow_semaphore")}(key text, holder text, max integer, ttl interval default '5 minutes')
returns boolean
language plpgsql
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_held integer;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('workflow_semaphore'), pg_catalog.hashtext(key));
  delete from ${m} x where x.${cm("key")} = key and x.${cm("expiresAt")} < now();
  update ${m} x set ${cm("expiresAt")} = now() + coalesce(ttl, interval '5 minutes')
  where x.${cm("key")} = key and x.${cm("holder")} = holder;
  if found then
    return true;
  end if;
  select count(*) into v_held from ${m} x where x.${cm("key")} = key;
  if v_held >= greatest(coalesce(max, 1), 1) then
    return false;
  end if;
  insert into ${m} (${cm("key")}, ${cm("holder")}, ${cm("expiresAt")})
  values (key, holder, now() + coalesce(ttl, interval '5 minutes'));
  return true;
end;
$$;
${serviceGrant(`${fn("acquire_workflow_semaphore")}(text, text, integer, interval)`)}

create or replace function ${fn("release_workflow_semaphore")}(key text, holder text)
returns boolean
language plpgsql
set search_path = ''
as $$
#variable_conflict use_variable
begin
  delete from ${m} x where x.${cm("key")} = key and x.${cm("holder")} = holder;
  return found;
end;
$$;
${serviceGrant(`${fn("release_workflow_semaphore")}(text, text)`)}

-- Whether a start request with key is active: waiting, leased, or started
-- with a run that hasn't finished (a run no engine reports counts for a day).
create or replace function ${fn("workflow_admission_active")}(key text)
returns integer
language sql
stable
set search_path = ''
as $$
  select count(*)::integer from ${q} x
  where x.${cq("key")} = workflow_admission_active.key
    and (
      (x.${cq("status")} = 'pending' and x.${cq("claimedUntil")} >= now())
      or (x.${cq("status")} = 'started' and not exists (
        select 1 from ${r} y
        where y.${cr("externalId")} = x.${cq("runId")} and y.${cr("status")} in ${TERMINAL}
      ) and x.${cq("startedAt")} > now() - interval '1 day')
    );
$$;
${serviceGrant(`${fn("workflow_admission_active")}(text)`)}

-- Queues a start under key: { id, status }. payload is { input }, the
-- workflow's arguments. singleton drops it ('dropped') while a run with key
-- is active; debounce replaces the waiting request and waits that long;
-- concurrency caps the runs started at once. subject_type and subject_id
-- name the record the run belongs to.
drop function if exists ${fn("request_workflow_start")}(text, text, jsonb, ${id}, uuid, integer, interval, boolean);
create or replace function ${fn("request_workflow_start")}(
  key text,
  workflow text,
  payload jsonb default '{}'::jsonb,
  tenant ${id} default null,
  actor uuid default null,
  concurrency integer default null,
  debounce interval default null,
  singleton boolean default false,
  subject_type text default null,
  subject_id text default null
)
returns jsonb
language plpgsql
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
begin${
    linked && queued
      ? ""
      : `
  if subject_type is not null or subject_id is not null then
    ${fail("WORKFLOW_SUBJECT_UNSUPPORTED", "this workflow runs table has no subject columns", "22023")}
  end if;`
  }
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('workflow_admission'), pg_catalog.hashtext(key));
  if coalesce(singleton, false) and (
    ${fn("workflow_admission_active")}(key) > 0
    or exists (select 1 from ${q} x where x.${cq("key")} = key and x.${cq("status")} = 'pending')
  ) then
    return jsonb_build_object('id', null, 'status', 'dropped');
  end if;
  if debounce is not null then
    update ${q} x set ${cq("status")} = ${ctx.cast("startRequests", "status", "'superseded'")}
    where x.${cq("key")} = key and x.${cq("status")} = 'pending'
      and (x.${cq("claimedUntil")} is null or x.${cq("claimedUntil")} < now());
  end if;
  insert into ${q} (${cq("key")}, ${cq("workflow")}, ${cq("input")}, ${cq("tenant")}, ${cq("actor")}, ${cq("concurrency")}, ${cq("notBefore")}${queued ? `, ${cq("subjectType")}, ${cq("subjectId")}` : ""})
  values (key, workflow, coalesce(payload -> 'input', '[]'::jsonb), tenant, actor, case when coalesce(singleton, false) then 1 else concurrency end, now() + coalesce(debounce, interval '0')${queued ? ", subject_type, subject_id" : ""})
  returning ${cq("id")} into v_id;
  return jsonb_build_object('id', v_id, 'status', 'pending');
end;
$$;
${serviceGrant(`${fn("request_workflow_start")}(text, text, jsonb, ${id}, uuid, integer, interval, boolean, text, text)`)}

-- Leases up to batch start requests whose time came and whose key has room:
-- [{ id, key, workflow, input, tenant, actor, subjectType, subjectId }]. Start each, then call
-- mark_workflow_start_request; a lease that runs out frees the request.
create or replace function ${fn("claim_workflow_start_requests")}(lease integer default 60, batch integer default 50)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_row ${q}%rowtype;
  v_out jsonb := '[]'::jsonb;
  v_taken integer := 0;
begin
  for v_row in
    select * from ${q}
    where ${cq("status")} = 'pending'
      and ${cq("notBefore")} <= now()
      and (${cq("claimedUntil")} is null or ${cq("claimedUntil")} < now())
    order by ${cq("createdAt")}
    for update skip locked
  loop
    exit when v_taken >= greatest(coalesce(batch, 50), 1);
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('workflow_admission'), pg_catalog.hashtext(v_row.${cq("key")}));
    if v_row.${cq("concurrency")} is null
      or ${fn("workflow_admission_active")}(v_row.${cq("key")}) < v_row.${cq("concurrency")} then
      update ${q} set ${cq("claimedUntil")} = now() + make_interval(secs => greatest(coalesce(lease, 60), 1))
      where ${cq("id")} = v_row.${cq("id")};
      v_out := v_out || jsonb_build_array(jsonb_build_object(
        'id', v_row.${cq("id")},
        'key', v_row.${cq("key")},
        'workflow', v_row.${cq("workflow")},
        'input', v_row.${cq("input")},
        'tenant', v_row.${cq("tenant")},
        'actor', v_row.${cq("actor")},
        'subjectType', ${queued ? `v_row.${cq("subjectType")}` : "null"},
        'subjectId', ${queued ? `v_row.${cq("subjectId")}` : "null"}
      ));
      v_taken := v_taken + 1;
    end if;
  end loop;
  return v_out;
end;
$$;
${serviceGrant(`${fn("claim_workflow_start_requests")}(integer, integer)`)}

-- Records the run a claimed request started.
create or replace function ${fn("mark_workflow_start_request")}(request uuid, run text)
returns boolean
language plpgsql
set search_path = ''
as $$
#variable_conflict use_variable
begin
  update ${q} x set ${cq("status")} = ${ctx.cast("startRequests", "status", "'started'")}, ${cq("runId")} = run, ${cq("startedAt")} = now(), ${cq("claimedUntil")} = null
  where x.${cq("id")} = request and x.${cq("status")} = 'pending';
  return found;
end;
$$;
${serviceGrant(`${fn("mark_workflow_start_request")}(uuid, text)`)}

-- Members may join a run's topic when they can read the run, and a tenant's
-- topic with workflow.read in it. The pings carry the run id and status.
do $$
begin
  if to_regclass('realtime.messages') is not null then
    drop policy if exists ${receive} on realtime.messages;
    create policy ${receive} on realtime.messages for select to authenticated
      using (
        realtime.messages.extension = 'broadcast'
        and (
          (
            (select realtime.topic()) like 'workflow-run:%'
            and exists (
              select 1 from ${r} x
              where x.${cr("id")}::text = substr((select realtime.topic()), 14)
            )
          )
          or (
            (select realtime.topic()) like 'workflow-runs:%'
            and substr((select realtime.topic()), 15) in (
              select t::text from ${ctx.scope.ids(ctx.permission("read", permissions.read))} t
            )
          )
        )
      );
  end if;
end;
$$;`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "record_workflow_run",
      args: [
        "text",
        "text",
        "text",
        "text",
        "{id}",
        "uuid",
        "jsonb",
        "text",
        "timestamptz",
        "timestamptz",
        "text",
        "text",
        "text",
        "text",
        "text",
        "text",
      ],
      returns: "uuid",
    },
    {
      name: "workflow_runs_list",
      args: [
        "{id}",
        "text",
        "text",
        "integer",
        "timestamptz",
        "text",
        "text",
        "text",
      ],
      returns: "jsonb",
    },
    { name: "workflow_run_get", args: ["text"], returns: "jsonb" },
    { name: "request_workflow_cancel", args: ["text"], returns: "jsonb" },
    {
      name: "purge_workflow_runs",
      args: ["interval", "integer"],
      returns: "integer",
    },
    {
      name: "create_workflow_schedule",
      args: ["text", "text", "text", "timestamptz", "jsonb", "text", "{id}"],
      returns: "jsonb",
    },
    { name: "workflow_schedules_list", args: ["{id}"], returns: "jsonb" },
    {
      name: "pause_workflow_schedule",
      args: ["uuid", "boolean"],
      returns: "boolean",
    },
    { name: "remove_workflow_schedule", args: ["uuid"], returns: "boolean" },
    {
      name: "claim_due_workflow_schedules",
      args: ["integer", "integer"],
      returns: "jsonb",
    },
    {
      name: "advance_workflow_schedule",
      args: ["uuid", "timestamptz", "timestamptz"],
      returns: "boolean",
    },
    {
      name: "acquire_workflow_semaphore",
      args: ["text", "text", "integer", "interval"],
      returns: "boolean",
    },
    {
      name: "release_workflow_semaphore",
      args: ["text", "text"],
      returns: "boolean",
    },
    {
      name: "request_workflow_start",
      args: [
        "text",
        "text",
        "jsonb",
        "{id}",
        "uuid",
        "integer",
        "interval",
        "boolean",
        "text",
        "text",
      ],
      returns: "jsonb",
    },
    {
      name: "claim_workflow_start_requests",
      args: ["integer", "integer"],
      returns: "jsonb",
    },
    {
      name: "mark_workflow_start_request",
      args: ["uuid", "text"],
      returns: "boolean",
    },
  ];
}

export const WORKFLOWS: BlockSqlDefinition = {
  name: "workflows",
  scopes: ["tenant"],
  title: "Workflows",
  description:
    "Engine-neutral workflow runs that members read through RLS, with a Realtime ping per status change and workflow_run.completed, .failed and .cancelled outbox events; cron schedules with idempotent fires, counting semaphores, admission control for starts (concurrency, debounce, singleton) and a retention purge.",
  requires: ["memberships", "permissions"],
  integrates: ["data-lifecycle"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 3,
  upgrades: [
    {
      from: 1,
      description:
        "workflow_runs and workflow_start_requests gain subject_type and subject_id; runs gain principal_kind, principal_id, mode and trigger_node; record_workflow_run, request_workflow_start and workflow_runs_list take the new arguments, and workflow_run.* events carry the subject.",
      sql: () => "",
    },
    {
      from: 2,
      description:
        "purge_workflow_runs keeps runs for the data-lifecycle retention policy and skips those under a legal hold.",
      sql: () => "",
    },
  ],
  names: NAMES,
  contract,
  build,
  topics: () => ["workflow-run:{runId}", "workflow-runs:{tenant}"],
};
