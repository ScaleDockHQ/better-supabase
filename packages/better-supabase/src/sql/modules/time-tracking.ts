import type { TimeTrackingEvents } from "../../blocks/time-tracking/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  addCheck,
  addExtraColumns,
  extraFieldsArg,
  extraFieldsJson,
  fail,
  lockTable,
  pageSize,
  schemaPreamble,
  SERVICE_CALLER,
  userGrant,
  writeExtraColumns,
} from "../shared.ts";
import { subjectReadable, subjectsOption } from "../subjects.ts";
import { OPERATIONS, moduleOperations } from "./access-model.ts";
import { policyOf, policySnapshot } from "./approvals-policies.ts";
import { TIMESHEET_SUBJECT } from "./approvals.ts";

const WHERE = "blocks.time-tracking.options";

const ENTRY_PAYLOAD = [
  "organizationId",
  "subjectType",
  "subjectId",
  "id",
  "userId",
  "startedAt",
] as const;

const RECORDED_PAYLOAD = [
  ...ENTRY_PAYLOAD,
  "seconds",
  "billable",
  "rate",
  "rateCurrency",
] as const;

const UPDATED_PAYLOAD = [...RECORDED_PAYLOAD, "previousStartedAt"] as const;

const TIMESHEET_PAYLOAD = [
  "organizationId",
  "id",
  "userId",
  "week",
  "approvalId",
] as const;

const EVENTS: BlockSqlEvents<TimeTrackingEvents> = {
  "time_entry.started": { subject: "time-entries", payload: ENTRY_PAYLOAD },
  "time_entry.recorded": { subject: "time-entries", payload: RECORDED_PAYLOAD },
  "time_entry.updated": { subject: "time-entries", payload: UPDATED_PAYLOAD },
  "time_entry.deleted": { subject: "time-entries", payload: ENTRY_PAYLOAD },
  "timesheet.submitted": { subject: "timesheets", payload: TIMESHEET_PAYLOAD },
  "timesheet.approved": { subject: "timesheets", payload: TIMESHEET_PAYLOAD },
  "timesheet.reopened": { subject: "timesheets", payload: TIMESHEET_PAYLOAD },
};

const NAMES: BlockSqlNames = {
  events: EVENTS,
  hooks: [
    "before_time_entry_save",
    "after_time_entry_save",
    "before_timesheet_submit",
    "after_timesheet_submit",
  ],
  options: ["subjects", "policy", "timeZone", "extraColumns"],
  tables: {
    entries: {
      name: "time_entries",
      lifecycle: { tenant: "tenant", user: "user", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        user: "user_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        startedAt: "started_at",
        endedAt: "ended_at",
        billable: "billable",
        rate: "rate",
        rateCurrency: "rate_currency",
        note: "note",
        createdAt: "created_at",
        updatedAt: "updated_at",
        seconds: "seconds",
      },
    },
    timesheets: {
      name: "timesheets",
      lifecycle: { tenant: "tenant", user: "user", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        user: "user_id",
        week: "week",
        approval: "approval_id",
        note: "note",
        submittedAt: "submitted_at",
        approvedAt: "approved_at",
        createdAt: "created_at",
      },
    },
  },
};

/** `options.timeZone`: the IANA zone weeks start in. Default `UTC`. */
/** The keys the entry reads return next to the extra columns. */
const RESERVED = ["fields"] as const;

function weekTimeZone(ctx: BlockSqlContext): string {
  const raw = ctx.option("timeZone") ?? "UTC";

  if (typeof raw !== "string" || raw.length === 0) {
    throw new TypeError(`${WHERE}.timeZone must be an IANA time zone`);
  }

  try {
    Intl.DateTimeFormat("en", { timeZone: raw });
  } catch {
    throw new TypeError(`${WHERE}.timeZone: "${raw}" is not a time zone`);
  }

  return raw;
}

/** `options.policy` as an approvals policy; defaults to one approver step. */
function timesheetPolicy(ctx: BlockSqlContext): string {
  const raw = ctx.option("policy") ?? {
    steps: [
      {
        approvers: {
          permission: ctx.permissionKey(
            "approve",
            OPERATIONS["time-tracking.approve"],
          ),
        },
      },
    ],
  };

  const policy = policyOf(TIMESHEET_SUBJECT, "approve", raw, `${WHERE}.policy`);

  if (policy.run !== undefined) {
    throw new TypeError(
      `${WHERE}.policy.run is not allowed; the final approval locks the week`,
    );
  }

  return policySnapshot(policy);
}

/**
 * The rate's currency is an uppercase three-letter code (the client checks it
 * against ISO 4217) and is set exactly when the rate is. Added once, so new and
 * upgraded tables carry the same named checks.
 */
function rateChecks(ctx: BlockSqlContext): string {
  const entries = ctx.table("entries");
  const name = ctx.tableName("entries").name;
  const rate = ctx.col("entries", "rate");
  const currency = ctx.col("entries", "rateCurrency");

  return `${addCheck({
    table: entries,
    name: `${name}_rate_currency_check`,
    expression: `${currency} is null or ${currency} ~ '^[A-Z]{3}$'`,
  })}
${addCheck({
  table: entries,
  name: `${name}_rate_pair_check`,
  expression: `(${rate} is null) = (${currency} is null)`,
})}`;
}

/** The functions' signatures before the rate became minor units and a currency. */
const NUMERIC_SIGNATURES = {
  start_timer: (id: string) => `${id}, text, text, boolean, numeric, text`,
  log_time: (id: string) =>
    `${id}, timestamptz, timestamptz, text, text, boolean, numeric, text, uuid`,
};

function dropNumericSignatures(ctx: BlockSqlContext): string {
  return Object.entries(NUMERIC_SIGNATURES)
    .flatMap(([name, types]) => [
      `drop function if exists ${ctx.fn(name)}(${types(ctx.idType)});`,
      `drop function if exists ${ctx.fn(name)}(${types(ctx.idType)}, jsonb);`,
    ])
    .join("\n");
}

/**
 * Version 1 stored the rate as `numeric(12, 2)` with no currency. Its two
 * decimals become minor units (times 100), and rates stay without a currency
 * until the app sets one; the pair check then warns.
 */
function upgradeRateToMoney(ctx: BlockSqlContext): string {
  if (!ctx.manages) {
    return dropNumericSignatures(ctx);
  }

  const entries = ctx.table("entries");
  const { schema, name } = ctx.tableName("entries");
  const rate = ctx.col("entries", "rate");

  return `${dropNumericSignatures(ctx)}
alter table ${entries} add column if not exists ${ctx.col("entries", "rateCurrency")} text;
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = ${sqlString(schema)} and table_name = ${sqlString(name)}
      and column_name = ${sqlString(rate.replaceAll('"', ""))} and data_type = 'numeric'
  ) then
    alter table ${entries} alter column ${rate} type bigint using round(${rate} * 100)::bigint;
  end if;
end;
$$;
${rateChecks(ctx)}`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const approvals = ctx.of("approvals");

  if (approvals.mode === "custom") {
    throw new TypeError(
      "blocks.time-tracking needs the approvals tables; approvals can't be in custom mode",
    );
  }

  const entries = ctx.table("entries");
  const timesheets = ctx.table("timesheets");
  const e = (column: string): string => ctx.col("entries", column);
  const t = (column: string): string => ctx.col("timesheets", column);
  const ar = approvals.table("requests");
  const a = (column: string): string => approvals.col("requests", column);
  const fn = (name: string): string => ctx.fn(name);
  const permissions = moduleOperations("time-tracking");
  const read = ctx.permission("read", permissions.read);
  const track = ctx.permission("track", permissions.track);
  const manage = ctx.permission("manage", permissions.manage);
  const subjects = subjectsOption(ctx);
  const zone = sqlString(weekTimeZone(ctx));
  const policy = timesheetPolicy(ctx);
  const members = ctx.of("tenant");

  const isMember = (tenant: string, user: string): string =>
    `exists (select 1 from ${members.table("memberships")} m where m.${members.col("memberships", "tenant")} = ${tenant} and m.${members.col("memberships", "user")} = ${user})`;

  const forbidden = (message: string): string =>
    fail("TIME_FORBIDDEN", message);

  const entryNotFound = fail(
    "TIME_ENTRY_NOT_FOUND",
    "time entry not found",
    "P0002",
  );

  const timesheetNotFound = fail(
    "TIMESHEET_NOT_FOUND",
    "timesheet not found",
    "P0002",
  );

  const extras = ctx.extraColumns("entries", RESERVED);
  const extra = extraFieldsArg(extras);

  const setExtras = (source: string): string =>
    writeExtraColumns(
      entries,
      extras,
      source,
      `x.${e("id")} = v_row.${e("id")}`,
      "v_row",
    );

  const seconds = (row: string): string =>
    `case when ${row}.${e("endedAt")} is null then null else extract(epoch from ${row}.${e("endedAt")} - ${row}.${e("startedAt")})::bigint end`;

  const entryJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${e("id")}, 'organizationId', ${row}.${e("tenant")}, 'userId', ${row}.${e("user")}, 'subjectType', ${row}.${e("subjectType")}, 'subjectId', ${row}.${e("subjectId")}, 'startedAt', ${row}.${e("startedAt")}, 'endedAt', ${row}.${e("endedAt")}, 'seconds', ${seconds(row)}, 'billable', ${row}.${e("billable")}, 'rate', ${row}.${e("rate")}::text, 'rateCurrency', ${row}.${e("rateCurrency")}, 'note', ${row}.${e("note")}, 'createdAt', ${row}.${e("createdAt")}, 'updatedAt', ${row}.${e("updatedAt")}${extraFieldsJson(row, extras)})`;

  const status = (row: string, approval: string): string =>
    `case when ${row}.${t("approvedAt")} is not null then 'approved' when ${approval}.${a("status")} = 'pending' then 'submitted' when ${approval}.${a("status")} = 'rejected' then 'rejected' else 'open' end`;

  const timesheetJson = (row: string, approval: string): string =>
    `jsonb_build_object('id', ${row}.${t("id")}, 'organizationId', ${row}.${t("tenant")}, 'userId', ${row}.${t("user")}, 'week', ${row}.${t("week")}, 'status', ${status(row, approval)}, 'approvalId', ${row}.${t("approval")}, 'note', ${row}.${t("note")}, 'submittedAt', ${row}.${t("submittedAt")}, 'approvedAt', ${row}.${t("approvedAt")}, 'createdAt', ${row}.${t("createdAt")})`;

  const entryRecord = (
    type: string,
    row: string,
    recorded: boolean,
    previousStartedAt?: string,
  ): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', ${row}.${e("tenant")}, 'subjectType', ${row}.${e("subjectType")}, 'subjectId', ${row}.${e("subjectId")}, 'id', ${row}.${e("id")}, 'userId', ${row}.${e("user")}, 'startedAt', ${row}.${e("startedAt")}${recorded ? `, 'seconds', ${seconds(row)}, 'billable', ${row}.${e("billable")}, 'rate', ${row}.${e("rate")}::text, 'rateCurrency', ${row}.${e("rateCurrency")}` : ""}${previousStartedAt === undefined ? "" : `, 'previousStartedAt', ${previousStartedAt}`})`,
      subject: `'time-entries/' || ${row}.${e("id")}::text`,
      tenant: `${row}.${e("tenant")}`,
      audit: false,
    });

  const timesheetRecord = (
    type: string,
    row: string,
    summary: string,
  ): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', ${row}.${t("tenant")}, 'id', ${row}.${t("id")}, 'userId', ${row}.${t("user")}, 'week', ${row}.${t("week")}, 'approvalId', ${row}.${t("approval")})`,
      subject: `'timesheets/' || ${row}.${t("id")}::text`,
      tenant: `${row}.${t("tenant")}`,
      audit: {
        category: "data",
        targetType: "timesheet",
        recordId: `${row}.${t("id")}::text`,
        summary: `${sqlString(summary)} || ' for the week of ' || ${row}.${t("week")}::text`,
      },
    });

  const subjectCheck = (
    tenant: string,
    type: string,
    id: string,
  ): string => `if (${type} is null) <> (${id} is null) then
    ${fail("TIME_SUBJECT_INVALID", "name both subject_type and subject_id, or neither", "22023")}
  end if;
  if ${type} is not null and not (${SERVICE_CALLER} or ${subjectReadable(ctx, subjects, { type, id, tenant })}) then
    ${forbidden("not allowed to track time on this record")}
  end if;`;

  const rateCheck = (
    rate: string,
    currency: string,
  ): string => `if (${rate} is null) <> (${currency} is null) then
    ${fail("TIME_RATE_INVALID", "name both rate and rate_currency, or neither", "22023")}
  end if;
  if ${currency} !~ '^[A-Z]{3}$' then
    ${fail("TIME_RATE_INVALID", "rate_currency must be a three-letter currency code", "22023")}
  end if;`;

  const overlap = (row: string): string => `if exists (
    select 1 from ${entries} x
    where x.${e("tenant")} = ${row}.${e("tenant")} and x.${e("user")} = ${row}.${e("user")} and x.${e("id")} <> ${row}.${e("id")}
      and tstzrange(x.${e("startedAt")}, coalesce(x.${e("endedAt")}, 'infinity'::timestamptz)) && tstzrange(${row}.${e("startedAt")}, coalesce(${row}.${e("endedAt")}, 'infinity'::timestamptz))
  ) then
    ${fail("TIME_ENTRY_OVERLAP", "this time overlaps another entry", "23P01")}
  end if;`;

  const save = (row: string): string =>
    ctx.hook("before_time_entry_save", [
      ["uuid", `${row}.${e("id")}`],
      [ctx.idType, `${row}.${e("tenant")}`],
      ["uuid", `${row}.${e("user")}`],
    ]);

  const saved = (row: string): string =>
    ctx.hook("after_time_entry_save", [["uuid", `${row}.${e("id")}`]]);

  const tables = ctx.manages
    ? `create extension if not exists btree_gist with schema extensions;

create table if not exists ${entries} (
  ${e("id")} uuid primary key default gen_random_uuid(),
  ${e("tenant")} ${ctx.idType} not null,
  ${e("user")} uuid not null,
  ${e("subjectType")} text,
  ${e("subjectId")} text,
  ${e("startedAt")} timestamptz not null,
  ${e("endedAt")} timestamptz,
  ${e("billable")} boolean not null default false,
  -- Minor units of rate_currency per hour (ADR 0037).
  ${e("rate")} bigint check (${e("rate")} is null or ${e("rate")} >= 0),
  ${e("rateCurrency")} text,
  ${e("note")} text check (${e("note")} is null or length(${e("note")}) <= 2000),
  ${e("createdAt")} timestamptz not null default now(),
  ${e("updatedAt")} timestamptz not null default now(),
  -- What metrics sum: the length of a finished entry, null while it runs.
  ${e("seconds")} bigint generated always as (extract(epoch from ${e("endedAt")} - ${e("startedAt")})::bigint) stored,
  check (${e("endedAt")} is null or ${e("endedAt")} > ${e("startedAt")}),
  check ((${e("subjectType")} is null) = (${e("subjectId")} is null)),
  -- A running entry reaches to infinity, so this also allows one running timer per user.
  constraint ${sqlIdent(`${ctx.tableName("entries").name}_no_overlap`)} exclude using gist (
    ${e("tenant")} with =,
    ${e("user")} with =,
    tstzrange(${e("startedAt")}, coalesce(${e("endedAt")}, 'infinity'::timestamptz)) with &&
  )
);${addExtraColumns(entries, extras)}
alter table ${entries} add column if not exists ${e("rateCurrency")} text;
${rateChecks(ctx)}
create unique index if not exists ${sqlIdent(`${ctx.tableName("entries").name}_running_idx`)} on ${entries} (${e("tenant")}, ${e("user")}) where ${e("endedAt")} is null;
create index if not exists ${sqlIdent(`${ctx.tableName("entries").name}_user_idx`)} on ${entries} (${e("tenant")}, ${e("user")}, ${e("startedAt")} desc);
create index if not exists ${sqlIdent(`${ctx.tableName("entries").name}_subject_idx`)} on ${entries} (${e("tenant")}, ${e("subjectType")}, ${e("subjectId")}) where ${e("subjectType")} is not null;
${lockTable(entries, { read: true })}
drop policy if exists "time_entries_read" on ${entries};
create policy "time_entries_read" on ${entries} for select to authenticated
  using (${e("user")} = (select auth.uid()) or ${ctx.scope.check(e("tenant"), read)});

create table if not exists ${timesheets} (
  ${t("id")} uuid primary key default gen_random_uuid(),
  ${t("tenant")} ${ctx.idType} not null,
  ${t("user")} uuid not null,
  ${t("week")} date not null check (extract(isodow from ${t("week")}) = 1),
  ${t("approval")} uuid references ${ar} (${a("id")}) on delete set null,
  ${t("note")} text check (${t("note")} is null or length(${t("note")}) <= 2000),
  ${t("submittedAt")} timestamptz,
  ${t("approvedAt")} timestamptz,
  ${t("createdAt")} timestamptz not null default now(),
  unique (${t("tenant")}, ${t("user")}, ${t("week")})
);
create index if not exists ${sqlIdent(`${ctx.tableName("timesheets").name}_approval_idx`)} on ${timesheets} (${t("approval")}) where ${t("approval")} is not null;
create index if not exists ${sqlIdent(`${ctx.tableName("timesheets").name}_week_idx`)} on ${timesheets} (${t("tenant")}, ${t("week")} desc);
${lockTable(timesheets, { read: true })}
drop policy if exists "timesheets_read" on ${timesheets};
create policy "timesheets_read" on ${timesheets} for select to authenticated
  using (${t("user")} = (select auth.uid()) or ${ctx.scope.check(t("tenant"), read)});
`
    : "";

  return `${schemaPreamble(ctx)}
${tables}
-- The Monday of the week an instant falls in, in options.timeZone.
create or replace function ${fn("time_week")}(at timestamptz)
returns date
language sql
stable
set search_path = ''
as $$
  select (date_trunc('week', time_week.at at time zone ${zone}))::date;
$$;
${userGrant(`${fn("time_week")}(timestamptz)`)}

-- A week is locked while its timesheet waits for approval and once it is approved.
create or replace function ${fn("time_week_locked")}(tenant ${ctx.idType}, user_id uuid, at timestamptz)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from ${timesheets} s
    left join ${ar} x on x.${a("id")} = s.${t("approval")}
    where s.${t("tenant")} = time_week_locked.tenant and s.${t("user")} = time_week_locked.user_id
      and s.${t("week")} = ${fn("time_week")}(time_week_locked.at)
      and (s.${t("approvedAt")} is not null or x.${a("status")} = 'pending')
  );
$$;
revoke execute on function ${fn("time_week_locked")}(${ctx.idType}, uuid, timestamptz) from public, anon, authenticated;

create or replace function ${fn("time_entry_guard")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') and ${fn("time_week_locked")}(old.${e("tenant")}, old.${e("user")}, old.${e("startedAt")}) then
    ${fail("TIME_PERIOD_LOCKED", "this week's timesheet is submitted or approved", "55000")}
  end if;
  if tg_op in ('INSERT', 'UPDATE') and ${fn("time_week_locked")}(new.${e("tenant")}, new.${e("user")}, new.${e("startedAt")}) then
    ${fail("TIME_PERIOD_LOCKED", "this week's timesheet is submitted or approved", "55000")}
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;
revoke execute on function ${fn("time_entry_guard")}() from public, anon, authenticated;
drop trigger if exists bsb_time_entry_guard on ${entries};
create trigger bsb_time_entry_guard
  before insert or update or delete on ${entries}
  for each row execute function ${fn("time_entry_guard")}();

-- Starts a timer for the caller, stopping the one that runs. fields: the
-- extra columns (blocks.time-tracking.options.extraColumns) to set.
${dropNumericSignatures(ctx)}
${extra.drop(fn("start_timer"), `${ctx.idType}, text, text, boolean, bigint, text, text`)}
create or replace function ${fn("start_timer")}(tenant ${ctx.idType}, subject_type text default null, subject_id text default null, billable boolean default false, rate bigint default null, rate_currency text default null, note text default null${extra.param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_at timestamptz := clock_timestamp();
  v_row ${entries}%rowtype;
begin
  if v_me is null or not ${ctx.can("tenant", "start_timer.tenant", track)} then
    ${forbidden("not allowed to track time here")}
  end if;
  ${subjectCheck("start_timer.tenant", "start_timer.subject_type", "start_timer.subject_id")}
  ${rateCheck("start_timer.rate", "start_timer.rate_currency")}
  perform pg_advisory_xact_lock(hashtextextended('time_entry:' || start_timer.tenant::text || ':' || v_me::text, 0));
  update ${entries} x set ${e("endedAt")} = v_at, ${e("updatedAt")} = v_at
    where x.${e("tenant")} = start_timer.tenant and x.${e("user")} = v_me and x.${e("endedAt")} is null
    returning * into v_row;
  if found then
    ${entryRecord("time_entry.recorded", "v_row", true)}
  end if;
  v_row := null;
  v_row.${e("id")} := gen_random_uuid();
  v_row.${e("tenant")} := start_timer.tenant;
  v_row.${e("user")} := v_me;
  v_row.${e("subjectType")} := start_timer.subject_type;
  v_row.${e("subjectId")} := start_timer.subject_id;
  v_row.${e("startedAt")} := v_at;
  v_row.${e("billable")} := coalesce(start_timer.billable, false);
  v_row.${e("rate")} := start_timer.rate;
  v_row.${e("rateCurrency")} := start_timer.rate_currency;
  v_row.${e("note")} := start_timer.note;
  ${overlap("v_row")}
  ${save("v_row")}
  insert into ${entries} (${e("id")}, ${e("tenant")}, ${e("user")}, ${e("subjectType")}, ${e("subjectId")}, ${e("startedAt")}, ${e("billable")}, ${e("rate")}, ${e("rateCurrency")}, ${e("note")})
  values (v_row.${e("id")}, v_row.${e("tenant")}, v_row.${e("user")}, v_row.${e("subjectType")}, v_row.${e("subjectId")}, v_row.${e("startedAt")}, v_row.${e("billable")}, v_row.${e("rate")}, v_row.${e("rateCurrency")}, v_row.${e("note")})
  returning * into v_row;${setExtras("start_timer.fields")}
  ${entryRecord("time_entry.started", "v_row", false)}
  ${saved("v_row")}
  return ${entryJson("v_row")};
end;
$$;
${userGrant(`${fn("start_timer")}(${ctx.idType}, text, text, boolean, bigint, text, text${extra.type})`)}

create or replace function ${fn("stop_timer")}(tenant ${ctx.idType})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_at timestamptz := clock_timestamp();
  v_row ${entries}%rowtype;
begin
  select * into v_row from ${entries} x
    where x.${e("tenant")} = stop_timer.tenant and x.${e("user")} = v_me and x.${e("endedAt")} is null
    for update;
  if not found then
    ${fail("TIME_NO_TIMER", "no timer is running", "P0002")}
  end if;
  update ${entries} x set ${e("endedAt")} = v_at, ${e("updatedAt")} = v_at
    where x.${e("id")} = v_row.${e("id")}
    returning * into v_row;
  ${entryRecord("time_entry.recorded", "v_row", true)}
  ${saved("v_row")}
  return ${entryJson("v_row")};
end;
$$;
${userGrant(`${fn("stop_timer")}(${ctx.idType})`)}

-- The caller's running timer, or null.
create or replace function ${fn("running_timer")}(tenant ${ctx.idType})
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select ${entryJson("x")} from ${entries} x
  where x.${e("tenant")} = running_timer.tenant and x.${e("user")} = auth.uid() and x.${e("endedAt")} is null;
$$;
${userGrant(`${fn("running_timer")}(${ctx.idType})`)}

-- Records finished time. Logging for another member needs the manage permission.
${extra.drop(fn("log_time"), `${ctx.idType}, timestamptz, timestamptz, text, text, boolean, bigint, text, text, uuid`)}
create or replace function ${fn("log_time")}(tenant ${ctx.idType}, started_at timestamptz, ended_at timestamptz, subject_type text default null, subject_id text default null, billable boolean default false, rate bigint default null, rate_currency text default null, note text default null, user_id uuid default null${extra.param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_user uuid := coalesce(log_time.user_id, auth.uid());
  v_row ${entries}%rowtype;
begin
  if v_user is null then
    ${forbidden("sign in to track time")}
  end if;
  if v_user = v_me then
    if not ${ctx.can("tenant", "log_time.tenant", track)} then
      ${forbidden("not allowed to track time here")}
    end if;
  elsif not (${SERVICE_CALLER} or ${ctx.can("tenant", "log_time.tenant", manage)}) then
    ${forbidden("not allowed to log time for another member")}
  elsif not ${isMember("log_time.tenant", "v_user")} then
    ${fail("TIME_USER_INVALID", "that user isn't a member of this organization", "22023")}
  end if;
  if log_time.started_at is null or log_time.ended_at is null or log_time.ended_at <= log_time.started_at then
    ${fail("TIME_ENTRY_INVALID", "ended_at must be after started_at", "22023")}
  end if;
  ${subjectCheck("log_time.tenant", "log_time.subject_type", "log_time.subject_id")}
  ${rateCheck("log_time.rate", "log_time.rate_currency")}
  perform pg_advisory_xact_lock(hashtextextended('time_entry:' || log_time.tenant::text || ':' || v_user::text, 0));
  v_row.${e("id")} := gen_random_uuid();
  v_row.${e("tenant")} := log_time.tenant;
  v_row.${e("user")} := v_user;
  v_row.${e("subjectType")} := log_time.subject_type;
  v_row.${e("subjectId")} := log_time.subject_id;
  v_row.${e("startedAt")} := log_time.started_at;
  v_row.${e("endedAt")} := log_time.ended_at;
  v_row.${e("billable")} := coalesce(log_time.billable, false);
  v_row.${e("rate")} := log_time.rate;
  v_row.${e("rateCurrency")} := log_time.rate_currency;
  v_row.${e("note")} := log_time.note;
  ${overlap("v_row")}
  ${save("v_row")}
  insert into ${entries} (${e("id")}, ${e("tenant")}, ${e("user")}, ${e("subjectType")}, ${e("subjectId")}, ${e("startedAt")}, ${e("endedAt")}, ${e("billable")}, ${e("rate")}, ${e("rateCurrency")}, ${e("note")})
  values (v_row.${e("id")}, v_row.${e("tenant")}, v_row.${e("user")}, v_row.${e("subjectType")}, v_row.${e("subjectId")}, v_row.${e("startedAt")}, v_row.${e("endedAt")}, v_row.${e("billable")}, v_row.${e("rate")}, v_row.${e("rateCurrency")}, v_row.${e("note")})
  returning * into v_row;${setExtras("log_time.fields")}
  ${entryRecord("time_entry.recorded", "v_row", true)}
  ${saved("v_row")}
  return ${entryJson("v_row")};
end;
$$;
${userGrant(`${fn("log_time")}(${ctx.idType}, timestamptz, timestamptz, text, text, boolean, bigint, text, text, uuid${extra.type})`)}

-- Changes the keys in patch: startedAt, endedAt, subjectType and subjectId
-- together, billable, rate and rateCurrency together (minor units per
-- hour as text), note and fields (the extra columns).
create or replace function ${fn("update_time_entry")}(entry_id uuid, patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${entries}%rowtype;
  v_patch jsonb := coalesce(update_time_entry.patch, '{}'::jsonb);
  v_previous_started_at timestamptz;
begin
  select * into v_row from ${entries} x where x.${e("id")} = update_time_entry.entry_id for update;
  if not found then
    ${entryNotFound}
  end if;
  v_previous_started_at := v_row.${e("startedAt")};
  if not (${SERVICE_CALLER} or (v_row.${e("user")} = auth.uid() and ${ctx.can("tenant", `v_row.${e("tenant")}`, track)}) or ${ctx.can("tenant", `v_row.${e("tenant")}`, manage)}) then
    ${forbidden("not allowed to change this entry")}
  end if;
  if v_patch ? 'startedAt' then
    v_row.${e("startedAt")} := (v_patch ->> 'startedAt')::timestamptz;
  end if;
  if v_patch ? 'endedAt' then
    if v_patch ->> 'endedAt' is null then
      ${fail("TIME_ENTRY_INVALID", "a finished entry can't be restarted; start a timer instead", "22023")}
    end if;
    v_row.${e("endedAt")} := (v_patch ->> 'endedAt')::timestamptz;
  end if;
  if v_row.${e("startedAt")} is null or (v_row.${e("endedAt")} is not null and v_row.${e("endedAt")} <= v_row.${e("startedAt")}) then
    ${fail("TIME_ENTRY_INVALID", "ended_at must be after started_at", "22023")}
  end if;
  if v_patch ? 'subjectType' or v_patch ? 'subjectId' then
    v_row.${e("subjectType")} := v_patch ->> 'subjectType';
    v_row.${e("subjectId")} := v_patch ->> 'subjectId';
    ${subjectCheck(`v_row.${e("tenant")}`, `v_row.${e("subjectType")}`, `v_row.${e("subjectId")}`)}
  end if;
  if v_patch ? 'billable' then
    v_row.${e("billable")} := coalesce((v_patch ->> 'billable')::boolean, false);
  end if;
  if v_patch ? 'rate' or v_patch ? 'rateCurrency' then
    v_row.${e("rate")} := (v_patch ->> 'rate')::bigint;
    v_row.${e("rateCurrency")} := v_patch ->> 'rateCurrency';
    ${rateCheck(`v_row.${e("rate")}`, `v_row.${e("rateCurrency")}`)}
  end if;
  if v_patch ? 'note' then
    v_row.${e("note")} := v_patch ->> 'note';
  end if;
  ${overlap("v_row")}
  ${save("v_row")}
  update ${entries} x
  set ${e("startedAt")} = v_row.${e("startedAt")},
      ${e("endedAt")} = v_row.${e("endedAt")},
      ${e("subjectType")} = v_row.${e("subjectType")},
      ${e("subjectId")} = v_row.${e("subjectId")},
      ${e("billable")} = v_row.${e("billable")},
      ${e("rate")} = v_row.${e("rate")},
      ${e("rateCurrency")} = v_row.${e("rateCurrency")},
      ${e("note")} = v_row.${e("note")},
      ${e("updatedAt")} = now()
  where x.${e("id")} = v_row.${e("id")}
  returning * into v_row;${setExtras("(v_patch -> 'fields')")}
  ${entryRecord("time_entry.updated", "v_row", true, "v_previous_started_at")}
  ${saved("v_row")}
  return ${entryJson("v_row")};
end;
$$;
${userGrant(`${fn("update_time_entry")}(uuid, jsonb)`)}

create or replace function ${fn("delete_time_entry")}(entry_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${entries}%rowtype;
begin
  select * into v_row from ${entries} x where x.${e("id")} = delete_time_entry.entry_id for update;
  if not found then
    ${entryNotFound}
  end if;
  if not (${SERVICE_CALLER} or (v_row.${e("user")} = auth.uid() and ${ctx.can("tenant", `v_row.${e("tenant")}`, track)}) or ${ctx.can("tenant", `v_row.${e("tenant")}`, manage)}) then
    ${forbidden("not allowed to delete this entry")}
  end if;
  delete from ${entries} x where x.${e("id")} = v_row.${e("id")};
  ${entryRecord("time_entry.deleted", "v_row", false)}
  return ${entryJson("v_row")};
end;
$$;
${userGrant(`${fn("delete_time_entry")}(uuid)`)}

-- A member's entries (the caller's by default), or every member's on a
-- record with everyone. Other members' entries need the read permission.
create or replace function ${fn("list_time_entries")}(tenant ${ctx.idType}, user_id uuid default null, starts timestamptz default null, ends timestamptz default null, subject_type text default null, subject_id text default null, everyone boolean default false, page_size integer default 200)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := coalesce(list_time_entries.user_id, auth.uid());
  v_rows jsonb;
begin
  if not (${SERVICE_CALLER} or ((v_user = auth.uid() and not list_time_entries.everyone) and ${ctx.can("tenant", "list_time_entries.tenant", track)}) or ${ctx.can("tenant", "list_time_entries.tenant", read)}) then
    ${forbidden("not allowed to read these entries")}
  end if;
  select coalesce(jsonb_agg(${entryJson("q")} order by q.${e("startedAt")} desc), '[]'::jsonb) into v_rows
  from (
    select * from ${entries} x
    where x.${e("tenant")} = list_time_entries.tenant
      and (list_time_entries.everyone or x.${e("user")} = v_user)
      and (list_time_entries.starts is null or coalesce(x.${e("endedAt")}, 'infinity'::timestamptz) > list_time_entries.starts)
      and (list_time_entries.ends is null or x.${e("startedAt")} < list_time_entries.ends)
      and (list_time_entries.subject_type is null or x.${e("subjectType")} = list_time_entries.subject_type)
      and (list_time_entries.subject_id is null or x.${e("subjectId")} = list_time_entries.subject_id)
    order by x.${e("startedAt")} desc
    limit ${pageSize("list_time_entries.page_size", 200, 1000)}
  ) q;
  return v_rows;
end;
$$;
${userGrant(`${fn("list_time_entries")}(${ctx.idType}, uuid, timestamptz, timestamptz, text, text, boolean, integer)`)}

-- One member's week: the timesheet (status open when there is none yet),
-- the entries that start in it and their totals.
create or replace function ${fn("get_timesheet")}(tenant ${ctx.idType}, week date, user_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := coalesce(get_timesheet.user_id, auth.uid());
  v_week date := date_trunc('week', get_timesheet.week)::date;
  v_sheet ${timesheets}%rowtype;
  v_approval ${ar}%rowtype;
  v_json jsonb;
  v_entries jsonb;
  v_totals jsonb;
begin
  if not (${SERVICE_CALLER} or (v_user = auth.uid() and ${ctx.can("tenant", "get_timesheet.tenant", track)}) or ${ctx.can("tenant", "get_timesheet.tenant", read)}) then
    ${forbidden("not allowed to read this timesheet")}
  end if;
  select * into v_sheet from ${timesheets} s
    where s.${t("tenant")} = get_timesheet.tenant and s.${t("user")} = v_user and s.${t("week")} = v_week;
  if found then
    select * into v_approval from ${ar} x where x.${a("id")} = v_sheet.${t("approval")};
    v_json := ${timesheetJson("v_sheet", "v_approval")};
  else
    v_json := jsonb_build_object('id', null, 'organizationId', get_timesheet.tenant, 'userId', v_user, 'week', v_week, 'status', 'open');
  end if;
  select coalesce(jsonb_agg(${entryJson("x")} order by x.${e("startedAt")}), '[]'::jsonb),
    jsonb_build_object(
      'seconds', coalesce(sum(extract(epoch from coalesce(x.${e("endedAt")}, now()) - x.${e("startedAt")})), 0)::bigint,
      'billableSeconds', coalesce(sum(extract(epoch from coalesce(x.${e("endedAt")}, now()) - x.${e("startedAt")})) filter (where x.${e("billable")}), 0)::bigint,
      -- Billable hours times the rate, per currency, rounded to minor units.
      'amounts', (
        select coalesce(jsonb_agg(jsonb_build_object('amount', q.amount::text, 'currency', q.currency) order by q.currency), '[]'::jsonb)
        from (
          select y.${e("rateCurrency")} as currency,
            round(sum(extract(epoch from coalesce(y.${e("endedAt")}, now()) - y.${e("startedAt")}) * y.${e("rate")} / 3600))::bigint as amount
          from ${entries} y
          where y.${e("tenant")} = get_timesheet.tenant and y.${e("user")} = v_user
            and ${fn("time_week")}(y.${e("startedAt")}) = v_week
            and y.${e("billable")} and y.${e("rate")} is not null
          group by y.${e("rateCurrency")}
        ) q
      )
    )
    into v_entries, v_totals
  from ${entries} x
  where x.${e("tenant")} = get_timesheet.tenant and x.${e("user")} = v_user
    and ${fn("time_week")}(x.${e("startedAt")}) = v_week;
  return v_json || jsonb_build_object('entries', v_entries, 'totals', v_totals);
end;
$$;
${userGrant(`${fn("get_timesheet")}(${ctx.idType}, date, uuid)`)}

-- Sends the caller's week for approval. The week locks until a rejection.
create or replace function ${fn("submit_timesheet")}(tenant ${ctx.idType}, week date, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_week date := date_trunc('week', submit_timesheet.week)::date;
  v_sheet ${timesheets}%rowtype;
  v_approval ${ar}%rowtype;
  v_request jsonb;
  v_seconds bigint;
begin
  if v_me is null or not ${ctx.can("tenant", "submit_timesheet.tenant", track)} then
    ${forbidden("not allowed to submit a timesheet here")}
  end if;
  perform pg_advisory_xact_lock(hashtextextended('time_entry:' || submit_timesheet.tenant::text || ':' || v_me::text, 0));
  if exists (
    select 1 from ${entries} x
    where x.${e("tenant")} = submit_timesheet.tenant and x.${e("user")} = v_me and x.${e("endedAt")} is null
      and ${fn("time_week")}(x.${e("startedAt")}) = v_week
  ) then
    ${fail("TIMESHEET_TIMER_RUNNING", "stop the running timer before submitting this week", "55000")}
  end if;
  insert into ${timesheets} (${t("tenant")}, ${t("user")}, ${t("week")})
  values (submit_timesheet.tenant, v_me, v_week)
  on conflict (${t("tenant")}, ${t("user")}, ${t("week")}) do nothing;
  select * into v_sheet from ${timesheets} s
    where s.${t("tenant")} = submit_timesheet.tenant and s.${t("user")} = v_me and s.${t("week")} = v_week
    for update;
  if v_sheet.${t("approvedAt")} is not null then
    ${fail("TIMESHEET_APPROVED", "this week is already approved", "55000")}
  end if;
  select * into v_approval from ${ar} x where x.${a("id")} = v_sheet.${t("approval")};
  if v_approval.${a("status")} = 'pending' then
    ${fail("TIMESHEET_SUBMITTED", "this week is already waiting for approval", "55000")}
  end if;
  ${ctx.hook("before_timesheet_submit", [
    ["uuid", `v_sheet.${t("id")}`],
    [ctx.idType, "submit_timesheet.tenant"],
    ["date", "v_week"],
  ])}
  select coalesce(sum(extract(epoch from x.${e("endedAt")} - x.${e("startedAt")})), 0)::bigint into v_seconds
    from ${entries} x
    where x.${e("tenant")} = submit_timesheet.tenant and x.${e("user")} = v_me
      and ${fn("time_week")}(x.${e("startedAt")}) = v_week;
  v_request := ${approvals.fn("open_approval")}(
    submit_timesheet.tenant, ${sqlString(TIMESHEET_SUBJECT)}, v_sheet.${t("id")}::text, 'approve',
    ${sqlString(policy)}::jsonb, submit_timesheet.note,
    jsonb_build_object('userId', v_me, 'week', v_week, 'seconds', v_seconds)
  );
  update ${timesheets} s
  set ${t("approval")} = (v_request ->> 'id')::uuid, ${t("note")} = submit_timesheet.note, ${t("submittedAt")} = now()
  where s.${t("id")} = v_sheet.${t("id")}
  returning * into v_sheet;
  select * into v_approval from ${ar} x where x.${a("id")} = v_sheet.${t("approval")};
  ${timesheetRecord("timesheet.submitted", "v_sheet", "submitted a timesheet")}
  ${ctx.hook("after_timesheet_submit", [["uuid", `v_sheet.${t("id")}`]])}
  return ${timesheetJson("v_sheet", "v_approval")};
end;
$$;
${userGrant(`${fn("submit_timesheet")}(${ctx.idType}, date, text)`)}

-- Locks the week once the approval is final. Approvals calls it; it isn't
-- granted to anyone.
create or replace function ${fn("approve_timesheet")}(timesheet_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sheet ${timesheets}%rowtype;
begin
  update ${timesheets} s set ${t("approvedAt")} = now()
    where s.${t("id")} = approve_timesheet.timesheet_id and s.${t("approvedAt")} is null
    returning * into v_sheet;
  if found then
    ${timesheetRecord("timesheet.approved", "v_sheet", "approved a timesheet")}
  end if;
end;
$$;
revoke execute on function ${fn("approve_timesheet")}(uuid) from public, anon, authenticated;

-- Unlocks an approved week so its entries can change and it can be sent again.
create or replace function ${fn("reopen_timesheet")}(timesheet_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sheet ${timesheets}%rowtype;
  v_approval ${ar}%rowtype;
begin
  select * into v_sheet from ${timesheets} s where s.${t("id")} = reopen_timesheet.timesheet_id for update;
  if not found then
    ${timesheetNotFound}
  end if;
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", `v_sheet.${t("tenant")}`, manage)}) then
    ${forbidden("not allowed to reopen timesheets")}
  end if;
  if v_sheet.${t("approvedAt")} is null then
    ${fail("TIMESHEET_NOT_APPROVED", "only an approved week can be reopened", "55000")}
  end if;
  update ${timesheets} s set ${t("approvedAt")} = null, ${t("approval")} = null, ${t("submittedAt")} = null
    where s.${t("id")} = v_sheet.${t("id")}
    returning * into v_sheet;
  ${timesheetRecord("timesheet.reopened", "v_sheet", "reopened a timesheet")}
  return ${timesheetJson("v_sheet", "v_approval")};
end;
$$;
${userGrant(`${fn("reopen_timesheet")}(uuid)`)}

-- Newest week first: the caller's timesheets, or everyone's with the read permission.
create or replace function ${fn("list_timesheets")}(tenant ${ctx.idType}, user_id uuid default null, status text default null, page_size integer default 50, before date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_reader boolean := ${SERVICE_CALLER} or ${ctx.can("tenant", "list_timesheets.tenant", read)};
  v_rows jsonb;
begin
  if not (v_reader or ${ctx.can("tenant", "list_timesheets.tenant", track)}) then
    ${forbidden("not allowed to list timesheets")}
  end if;
  if not v_reader and list_timesheets.user_id is not null and list_timesheets.user_id <> auth.uid() then
    ${forbidden("not allowed to read another member's timesheets")}
  end if;
  select coalesce(jsonb_agg(q.item order by q.week desc, q.created desc), '[]'::jsonb) into v_rows
  from (
    select ${timesheetJson("s", "x")} as item, s.${t("week")} as week, s.${t("createdAt")} as created
    from ${timesheets} s
    left join ${ar} x on x.${a("id")} = s.${t("approval")}
    where s.${t("tenant")} = list_timesheets.tenant
      and (case when v_reader then list_timesheets.user_id is null or s.${t("user")} = list_timesheets.user_id else s.${t("user")} = auth.uid() end)
      and (list_timesheets.status is null or ${status("s", "x")} = list_timesheets.status)
      and (list_timesheets.before is null or s.${t("week")} < list_timesheets.before)
    order by s.${t("week")} desc, s.${t("createdAt")} desc
    limit ${pageSize("list_timesheets.page_size", 50, 200)}
  ) q;
  return v_rows;
end;
$$;
${userGrant(`${fn("list_timesheets")}(${ctx.idType}, uuid, text, integer, date)`)}
`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  const extra = extraFieldsArg(ctx.extraColumns("entries", RESERVED)).contract;

  return [
    {
      name: "start_timer",
      args: [
        "{id}",
        "text",
        "text",
        "boolean",
        "bigint",
        "text",
        "text",
        ...extra,
      ],
      returns: "jsonb",
    },
    { name: "stop_timer", args: ["{id}"], returns: "jsonb" },
    {
      name: "log_time",
      args: [
        "{id}",
        "timestamptz",
        "timestamptz",
        "text",
        "text",
        "boolean",
        "bigint",
        "text",
        "text",
        "uuid",
        ...extra,
      ],
      returns: "jsonb",
    },
    {
      name: "submit_timesheet",
      args: ["{id}", "date", "text"],
      returns: "jsonb",
    },
    { name: "get_timesheet", args: ["{id}", "date", "uuid"], returns: "jsonb" },
  ];
}

export const TIME_TRACKING: BlockSqlDefinition = {
  name: "time-tracking",
  scopes: ["tenant"],
  title: "Time tracking",
  description:
    "Time entries with one running timer per member and no overlaps, on any record, billable with a rate. Weekly timesheets go through approvals, and a submitted or approved week is locked.",
  requires: ["tenant", "access", "approvals"],
  integrates: ["outbox", "audit"],
  target: "schema",
  modes: ["managed", "adopt", "custom"],
  version: 2,
  upgrades: [
    {
      from: 1,
      description:
        "The rate is bigint minor units per hour with a rate_currency (ADR 0037); start_timer and log_time take rate_currency.",
      sql: upgradeRateToMoney,
    },
  ],
  names: NAMES,
  adoptOptional: () => ({ entries: ["seconds"] }),
  contract,
  build,
};
