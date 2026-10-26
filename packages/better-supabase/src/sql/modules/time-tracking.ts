import type { TimeTrackingEvents } from "../../blocks/time-tracking/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockContributes } from "../contributions.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import {
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
import { policyOf, policySnapshot } from "./approvals-policies.ts";
import { OPERATIONS, moduleOperations } from "./permissions-model.ts";
import { approvalTimesheetFunctions } from "./time-tracking-approvals.ts";
import {
  byEmployee,
  durationEntries,
  entryEnded,
  entrySubjects,
  timeOwner,
} from "./time-tracking-owner.ts";
import {
  dropNumericSignatures,
  rateChecks,
  upgradeRateToMoney,
} from "./time-tracking-rates.ts";
import {
  statusTimesheetFunctions,
  userTimeZoneOf,
  userWeekFunction,
} from "./time-tracking-status.ts";

/** Timesheets this block submits to approvals. */
const TIMESHEET_SUBJECT = "timesheet";

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
  "timesheet.rejected": { subject: "timesheets", payload: TIMESHEET_PAYLOAD },
};

const NAMES: BlockSqlNames = {
  entities: {
    entry: {
      table: "entries",
      singular: "time_entry",
      plural: "time_entries",
      primary: true,
    },
    timesheet: { table: "timesheets", singular: "timesheet" },
  },
  events: EVENTS,
  hooks: [
    "before_time_entry_save",
    "after_time_entry_save",
    "before_timesheet_submit",
    "after_timesheet_submit",
  ],
  options: [
    "policy",
    "timeZone",
    "extraColumns",
    "approvals",
    "userTimeZone",
    "owner",
  ],
  tables: {
    entries: {
      name: "time_entries",
      app: {
        unused: (ctx) =>
          byEmployee(ctx) ? ["seconds"] : ["seconds", "employee"],
      },
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
        runningSince: "running_since",
        employee: "employee_id",
      },
      optional: [
        "endedAt",
        "runningSince",
        "subjectType",
        "subjectId",
        "employee",
      ],
    },
    timesheets: {
      name: "timesheets",
      app: { unused: (ctx) => (byEmployee(ctx) ? [] : ["employee"]) },
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
        status: "status",
        decidedBy: "decided_by",
        decidedAt: "decided_at",
        decisionNote: "decision_note",
        employee: "employee_id",
      },
      optional: [
        "user",
        "employee",
        "approval",
        "status",
        "decidedBy",
        "decidedAt",
        "decisionNote",
      ],
      typed: ["status"],
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

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const statusMode = !ctx.flag("approvals", true);
  const approvals = statusMode ? undefined : ctx.of("approvals");

  if (approvals?.mode === "custom") {
    throw new TypeError(
      "blocks.time-tracking needs the approvals tables; approvals can't be in custom mode",
    );
  }

  if (statusMode && !ctx.has("timesheets", "status")) {
    throw new TypeError(
      `${WHERE}.approvals: false keeps the timesheet status in a column, so blocks.time-tracking.columns.timesheets.status can't be null`,
    );
  }

  const entries = ctx.table("entries");
  const timesheets = ctx.table("timesheets");
  const e = (column: string): string => ctx.col("entries", column);
  const t = (column: string): string => ctx.col("timesheets", column);
  const ar = approvals?.table("requests") ?? "";

  const a = (column: string): string =>
    approvals?.col("requests", column) ?? "";

  const fn = (name: string): string => ctx.fn(name);
  const permissions = moduleOperations("time-tracking");
  const read = ctx.permission("read", permissions.read);
  const track = ctx.permission("track", permissions.track);
  const manage = ctx.permission("manage", permissions.manage);
  const subjects = subjectsOption(ctx, ["column"]);

  const {
    bound,
    rowSubject,
    subjectColumns,
    setSubject,
    subjectInsert,
    subjectInsertValues,
  } = entrySubjects(ctx, subjects);

  const zone = sqlString(weekTimeZone(ctx));
  const userZone = userTimeZoneOf(ctx);
  const policy = statusMode ? "" : timesheetPolicy(ctx);

  const durationMode = durationEntries(ctx);

  if (
    durationMode &&
    (ctx.owns("entries") ||
      !ctx.has("entries", "seconds") ||
      !ctx.has("entries", "runningSince"))
  ) {
    throw new TypeError(
      "blocks.time-tracking.columns.entries.endedAt can be null only over your own entries table, with seconds (a writable duration column) and runningSince mapped",
    );
  }

  const owner = timeOwner(ctx, statusMode);

  const {
    employeeMode,
    staff,
    eOwner,
    tOwner,
    ownerVar,
    sheetUser,
    myEmployee,
    employeeOf,
    employeeOfUser,
    ownedByMe,
    sheetUserJson,
  } = owner;

  const ended = (alias: string): string => entryEnded(ctx, alias);

  // Whether row `alias` is a running timer.
  const running = (alias: string): string =>
    durationMode
      ? `${alias}.${ctx.col("entries", "runningSince")} is not null`
      : `${alias}.${ctx.col("entries", "endedAt")} is null`;

  // Stops the running row `alias` at `at`.
  const stop = (alias: string, at: string): string =>
    durationMode
      ? `${ctx.col("entries", "seconds")} = greatest(extract(epoch from ${at} - ${alias}.${ctx.col("entries", "startedAt")})::bigint, 0), ${ctx.col("entries", "runningSince")} = null`
      : `${ctx.col("entries", "endedAt")} = ${at}`;

  const endColumn = durationMode
    ? ctx.col("entries", "seconds")
    : ctx.col("entries", "endedAt");

  const patchedEnd = durationMode
    ? "v_ended"
    : `v_row.${ctx.col("entries", "endedAt")}`;

  // The Monday of the week of instant `at` for `user`.
  const weekOf = (at: string, user: string): string =>
    userZone === undefined
      ? `${fn("time_week")}(${at})`
      : `${fn("time_week")}(${at}, ${user})`;

  const members = ctx.of("memberships");

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
    durationMode
      ? `case when ${row}.${e("runningSince")} is null then ${row}.${e("seconds")}::bigint end`
      : `case when ${ended(row)} is null then null else extract(epoch from ${ended(row)} - ${row}.${e("startedAt")})::bigint end`;

  const entryJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${e("id")}, 'organizationId', ${row}.${e("tenant")}, 'userId', ${row}.${e("user")}${employeeMode ? `, 'employeeId', ${row}.${e("employee")}` : ""}, 'subjectType', ${rowSubject(row).type}, 'subjectId', ${rowSubject(row).id}, 'startedAt', ${row}.${e("startedAt")}, 'endedAt', ${ended(row)}, 'seconds', ${seconds(row)}, 'billable', ${row}.${e("billable")}, 'rate', ${row}.${e("rate")}::text, 'rateCurrency', ${row}.${e("rateCurrency")}, 'note', ${row}.${e("note")}, 'createdAt', ${row}.${e("createdAt")}, 'updatedAt', ${row}.${e("updatedAt")}${extraFieldsJson(row, extras)})`;

  const status = (row: string, approval: string): string =>
    statusMode
      ? ctx.label("timesheets", "status", `${row}.${t("status")}`)
      : `case when ${row}.${t("approvedAt")} is not null then 'approved' when ${approval}.${a("status")} = 'pending' then 'submitted' when ${approval}.${a("status")} = 'rejected' then 'rejected' else 'open' end`;

  const decision = (row: string): string =>
    statusMode
      ? (["decidedBy", "decidedAt", "decisionNote"] as const)
          .filter((logical) => ctx.has("timesheets", logical))
          .map((logical) => `, '${logical}', ${row}.${t(logical)}`)
          .join("")
      : "";

  const approvalOf = (row: string): string =>
    !statusMode && ctx.has("timesheets", "approval")
      ? `${row}.${t("approval")}`
      : "null::uuid";

  const timesheetJson = (row: string, approval: string): string =>
    `jsonb_build_object('id', ${row}.${t("id")}, 'organizationId', ${row}.${t("tenant")}, ${sheetUserJson(row)}, 'week', ${row}.${t("week")}, 'status', ${status(row, approval)}, 'approvalId', ${approvalOf(row)}, 'note', ${row}.${t("note")}, 'submittedAt', ${row}.${t("submittedAt")}, 'approvedAt', ${row}.${t("approvedAt")}, 'createdAt', ${row}.${t("createdAt")}${decision(row)})`;

  const entryRecord = (
    type: string,
    row: string,
    recorded: boolean,
    previousStartedAt?: string,
  ): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', ${row}.${e("tenant")}, 'subjectType', ${rowSubject(row).type}, 'subjectId', ${rowSubject(row).id}, 'id', ${row}.${e("id")}, 'userId', ${row}.${e("user")}${employeeMode ? `, 'employeeId', ${row}.${e("employee")}` : ""}, 'startedAt', ${row}.${e("startedAt")}${recorded ? `, 'seconds', ${seconds(row)}, 'billable', ${row}.${e("billable")}, 'rate', ${row}.${e("rate")}::text, 'rateCurrency', ${row}.${e("rateCurrency")}` : ""}${previousStartedAt === undefined ? "" : `, 'previousStartedAt', ${previousStartedAt}`})`,
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
      payload: `jsonb_build_object('organizationId', ${row}.${t("tenant")}, 'id', ${row}.${t("id")}, ${sheetUserJson(row)}, 'week', ${row}.${t("week")}, 'approvalId', ${approvalOf(row)})`,
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
    where x.${e("tenant")} = ${row}.${e("tenant")} and x.${eOwner} = ${row}.${eOwner} and x.${e("id")} <> ${row}.${e("id")}
      and tstzrange(x.${e("startedAt")}, coalesce(${ended("x")}, 'infinity'::timestamptz)) && tstzrange(${row}.${e("startedAt")}, coalesce(${ended(row)}, 'infinity'::timestamptz))
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
  ${e("user")} uuid${employeeMode ? `,\n  ${e("employee")} uuid not null` : " not null"},
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
    ${eOwner} with =,
    tstzrange(${e("startedAt")}, coalesce(${e("endedAt")}, 'infinity'::timestamptz)) with &&
  )
);${addExtraColumns(entries, extras)}
alter table ${entries} add column if not exists ${e("rateCurrency")} text;
${rateChecks(ctx)}
create unique index if not exists ${sqlIdent(`${ctx.tableName("entries").name}_running_idx`)} on ${entries} (${e("tenant")}, ${eOwner}) where ${e("endedAt")} is null;
create index if not exists ${sqlIdent(`${ctx.tableName("entries").name}_user_idx`)} on ${entries} (${e("tenant")}, ${eOwner}, ${e("startedAt")} desc);
create index if not exists ${sqlIdent(`${ctx.tableName("entries").name}_subject_idx`)} on ${entries} (${e("tenant")}, ${e("subjectType")}, ${e("subjectId")}) where ${e("subjectType")} is not null;
${lockTable(entries, { read: true })}
drop policy if exists ${ctx.naming.rename("time_entries_read")} on ${entries};
create policy ${ctx.naming.rename("time_entries_read")} on ${entries} for select to authenticated
  using (${e("user")} = (select auth.uid())${employeeMode ? ` or ${fn("time_is_my_employee")}(${e("tenant")}, ${e("employee")})` : ""} or ${ctx.scope.check(e("tenant"), read)});

create table if not exists ${timesheets} (
  ${t("id")} uuid primary key default gen_random_uuid(),
  ${t("tenant")} ${ctx.idType} not null,
  ${employeeMode ? `${sheetUser ? `${t("user")} uuid,\n  ` : ""}${t("employee")} uuid not null` : `${t("user")} uuid not null`},
  ${t("week")} date not null check (extract(isodow from ${t("week")}) = 1),
${
  statusMode
    ? `  ${t("status")} text not null default 'open' check (${t("status")} in ('open', 'submitted', 'approved', 'rejected')),${(
        [
          ["decidedBy", "uuid"],
          ["decidedAt", "timestamptz"],
          ["decisionNote", "text"],
        ] as const
      )
        .filter(([logical]) => ctx.has("timesheets", logical))
        .map(([logical, type]) => `\n  ${t(logical)} ${type},`)
        .join("")}`
    : `  ${t("approval")} uuid references ${ar} (${a("id")}) on delete set null,`
}
  ${t("note")} text check (${t("note")} is null or length(${t("note")}) <= 2000),
  ${t("submittedAt")} timestamptz,
  ${t("approvedAt")} timestamptz,
  ${t("createdAt")} timestamptz not null default now(),
  unique (${t("tenant")}, ${tOwner}, ${t("week")})
);
${statusMode ? "" : `create index if not exists ${sqlIdent(`${ctx.tableName("timesheets").name}_approval_idx`)} on ${timesheets} (${t("approval")}) where ${t("approval")} is not null;\n`}create index if not exists ${sqlIdent(`${ctx.tableName("timesheets").name}_week_idx`)} on ${timesheets} (${t("tenant")}, ${t("week")} desc);
${lockTable(timesheets, { read: true })}
drop policy if exists ${ctx.naming.rename("timesheets_read")} on ${timesheets};
create policy ${ctx.naming.rename("timesheets_read")} on ${timesheets} for select to authenticated
  using (${employeeMode ? `${sheetUser ? `${t("user")} = (select auth.uid()) or ` : ""}${fn("time_is_my_employee")}(${t("tenant")}, ${t("employee")})` : `${t("user")} = (select auth.uid())`} or ${ctx.scope.check(t("tenant"), read)});
`
    : "";

  const logTypes = `${ctx.idType}, timestamptz, timestamptz, text, text, boolean, bigint, text, text, uuid`;
  const listTypes = `${ctx.idType}, uuid, timestamptz, timestamptz, text, text, boolean, integer`;

  const dropSignatures = (name: string, types: string, fields = true): string =>
    [
      `drop function if exists ${name}(${types});`,
      ...(fields ? [`drop function if exists ${name}(${types}, jsonb);`] : []),
    ].join("\n");

  return `${schemaPreamble(ctx)}${owner.helper}
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
${userZone === undefined ? "" : userWeekFunction(ctx, userZone, zone)}
-- A week is locked while its timesheet waits for approval and once it is approved.
create or replace function ${fn("time_week_locked")}(tenant ${ctx.idType}, user_id uuid, at timestamptz)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from ${timesheets} s${statusMode ? "" : `\n    left join ${ar} x on x.${a("id")} = s.${t("approval")}`}
    where s.${t("tenant")} = time_week_locked.tenant and s.${tOwner} = time_week_locked.user_id
      and s.${t("week")} = ${weekOf("time_week_locked.at", "time_week_locked.user_id")}
      and ${statusMode ? ctx.is("timesheets", "status", `s.${t("status")}`, ["submitted", "approved"]) : `(s.${t("approvedAt")} is not null or x.${a("status")} = 'pending')`}
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
${
  employeeMode
    ? ""
    : `  -- employees keeps employee_id current, also on a locked week.
  if tg_op = 'UPDATE' and (to_jsonb(new) - 'employee_id') = (to_jsonb(old) - 'employee_id') then
    return new;
  end if;
`
}  if tg_op in ('UPDATE', 'DELETE') and ${fn("time_week_locked")}(old.${e("tenant")}, old.${eOwner}, old.${e("startedAt")}) then
    ${fail("TIME_PERIOD_LOCKED", "this week's timesheet is submitted or approved", "55000")}
  end if;
  if tg_op in ('INSERT', 'UPDATE') and ${fn("time_week_locked")}(new.${e("tenant")}, new.${eOwner}, new.${e("startedAt")}) then
    ${fail("TIME_PERIOD_LOCKED", "this week's timesheet is submitted or approved", "55000")}
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;
revoke execute on function ${fn("time_entry_guard")}() from public, anon, authenticated;
drop trigger if exists ${ctx.naming.rename("bsb_time_entry_guard")} on ${entries};
create trigger ${ctx.naming.rename("bsb_time_entry_guard")}
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
  v_row ${entries}%rowtype;${employeeMode ? "\n  v_owner uuid;" : ""}
begin
  if v_me is null or not ${ctx.can("tenant", "start_timer.tenant", track)} then
    ${forbidden("not allowed to track time here")}
  end if;${
    employeeMode
      ? `
  v_owner := ${myEmployee("start_timer.tenant")};
  if v_owner is null then
    ${fail("TIME_EMPLOYEE_MISSING", "you have no employee record in this organization", "22023")}
  end if;`
      : ""
  }
  ${subjectCheck("start_timer.tenant", "start_timer.subject_type", "start_timer.subject_id")}
  ${rateCheck("start_timer.rate", "start_timer.rate_currency")}
  perform pg_advisory_xact_lock(hashtextextended('time_entry:' || start_timer.tenant::text || ':' || ${ownerVar}::text, 0));
  update ${entries} x set ${stop("x", "v_at")}, ${e("updatedAt")} = v_at
    where x.${e("tenant")} = start_timer.tenant and x.${eOwner} = ${ownerVar} and ${running("x")}
    returning * into v_row;
  if found then
    ${entryRecord("time_entry.recorded", "v_row", true)}
  end if;
  v_row := null;
  v_row.${e("id")} := gen_random_uuid();
  v_row.${e("tenant")} := start_timer.tenant;
  v_row.${e("user")} := v_me;${employeeMode ? `\n  v_row.${e("employee")} := v_owner;` : ""}
  ${setSubject("start_timer.subject_type", "start_timer.subject_id", "  ")}
  v_row.${e("startedAt")} := v_at;${durationMode ? `\n  v_row.${e("runningSince")} := v_at;` : ""}
  v_row.${e("billable")} := coalesce(start_timer.billable, false);
  v_row.${e("rate")} := start_timer.rate;
  v_row.${e("rateCurrency")} := start_timer.rate_currency;
  v_row.${e("note")} := start_timer.note;
  ${overlap("v_row")}
  ${save("v_row")}
  insert into ${entries} (${e("id")}, ${e("tenant")}, ${e("user")}${employeeMode ? `, ${e("employee")}` : ""}, ${subjectInsert}, ${e("startedAt")}, ${e("billable")}, ${e("rate")}, ${e("rateCurrency")}, ${e("note")}${durationMode ? `, ${e("runningSince")}` : ""})
  values (v_row.${e("id")}, v_row.${e("tenant")}, v_row.${e("user")}${employeeMode ? `, v_row.${e("employee")}` : ""}, ${subjectInsertValues}, v_row.${e("startedAt")}, v_row.${e("billable")}, v_row.${e("rate")}, v_row.${e("rateCurrency")}, v_row.${e("note")}${durationMode ? `, v_row.${e("runningSince")}` : ""})
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
  v_row ${entries}%rowtype;${employeeMode ? `\n  v_owner uuid := ${myEmployee("stop_timer.tenant")};` : ""}
begin
  select * into v_row from ${entries} x
    where x.${e("tenant")} = stop_timer.tenant and x.${eOwner} = ${ownerVar} and ${running("x")}
    for update;
  if not found then
    ${fail("TIME_NO_TIMER", "no timer is running", "P0002")}
  end if;
  update ${entries} x set ${stop("x", "v_at")}, ${e("updatedAt")} = v_at
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
  where x.${e("tenant")} = running_timer.tenant and x.${e("user")} = auth.uid() and ${running("x")};
$$;
${userGrant(`${fn("running_timer")}(${ctx.idType})`)}

-- Records finished time. Logging for another member needs the manage permission.
${employeeMode ? `${dropSignatures(fn("log_time"), logTypes)}\n` : ""}${extra.drop(fn("log_time"), `${logTypes}${employeeMode ? ", uuid" : ""}`)}
create or replace function ${fn("log_time")}(tenant ${ctx.idType}, started_at timestamptz, ended_at timestamptz, subject_type text default null, subject_id text default null, billable boolean default false, rate bigint default null, rate_currency text default null, note text default null, user_id uuid default null${employeeMode ? ", employee_id uuid default null" : ""}${extra.param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
${
  employeeMode
    ? `  v_user uuid;
  v_owner uuid;
  v_row ${entries}%rowtype;
begin
  if log_time.employee_id is not null then
    ${employeeOf("log_time.tenant", "log_time.employee_id")}
  else
    ${employeeOfUser("log_time.tenant", "coalesce(log_time.user_id, v_me)")}
  end if;
  if v_owner is null then
    ${fail("TIME_EMPLOYEE_INVALID", "no employee record for that member in this organization", "22023")}
  end if;
  if v_me is not null and v_user = v_me then
    if not ${ctx.can("tenant", "log_time.tenant", track)} then
      ${forbidden("not allowed to track time here")}
    end if;
  elsif not (${SERVICE_CALLER} or ${ctx.can("tenant", "log_time.tenant", manage)}) then
    ${forbidden("not allowed to log time for another employee")}
  end if;`
    : `  v_user uuid := coalesce(log_time.user_id, auth.uid());
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
  end if;`
}
  if log_time.started_at is null or log_time.ended_at is null or log_time.ended_at <= log_time.started_at then
    ${fail("TIME_ENTRY_INVALID", "ended_at must be after started_at", "22023")}
  end if;
  ${subjectCheck("log_time.tenant", "log_time.subject_type", "log_time.subject_id")}
  ${rateCheck("log_time.rate", "log_time.rate_currency")}
  perform pg_advisory_xact_lock(hashtextextended('time_entry:' || log_time.tenant::text || ':' || ${employeeMode ? "v_owner" : "v_user"}::text, 0));
  v_row.${e("id")} := gen_random_uuid();
  v_row.${e("tenant")} := log_time.tenant;
  v_row.${e("user")} := v_user;${employeeMode ? `\n  v_row.${e("employee")} := v_owner;` : ""}
  ${setSubject("log_time.subject_type", "log_time.subject_id", "  ")}
  v_row.${e("startedAt")} := log_time.started_at;
  ${durationMode ? `v_row.${e("seconds")} := extract(epoch from log_time.ended_at - log_time.started_at)::bigint;` : `v_row.${e("endedAt")} := log_time.ended_at;`}
  v_row.${e("billable")} := coalesce(log_time.billable, false);
  v_row.${e("rate")} := log_time.rate;
  v_row.${e("rateCurrency")} := log_time.rate_currency;
  v_row.${e("note")} := log_time.note;
  ${overlap("v_row")}
  ${save("v_row")}
  insert into ${entries} (${e("id")}, ${e("tenant")}, ${e("user")}${employeeMode ? `, ${e("employee")}` : ""}, ${subjectInsert}, ${e("startedAt")}, ${endColumn}, ${e("billable")}, ${e("rate")}, ${e("rateCurrency")}, ${e("note")})
  values (v_row.${e("id")}, v_row.${e("tenant")}, v_row.${e("user")}${employeeMode ? `, v_row.${e("employee")}` : ""}, ${subjectInsertValues}, v_row.${e("startedAt")}, v_row.${endColumn}, v_row.${e("billable")}, v_row.${e("rate")}, v_row.${e("rateCurrency")}, v_row.${e("note")})
  returning * into v_row;${setExtras("log_time.fields")}
  ${entryRecord("time_entry.recorded", "v_row", true)}
  ${saved("v_row")}
  return ${entryJson("v_row")};
end;
$$;
${userGrant(`${fn("log_time")}(${logTypes}${employeeMode ? ", uuid" : ""}${extra.type})`)}

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
  v_previous_started_at timestamptz;${durationMode ? "\n  v_ended timestamptz;" : ""}
begin
  select * into v_row from ${entries} x where x.${e("id")} = update_time_entry.entry_id for update;
  if not found then
    ${entryNotFound}
  end if;
  v_previous_started_at := v_row.${e("startedAt")};${durationMode ? `\n  v_ended := ${ended("v_row")};` : ""}
  if not (${SERVICE_CALLER} or (${ownedByMe("v_row")} and ${ctx.can("tenant", `v_row.${e("tenant")}`, track)}) or ${ctx.can("tenant", `v_row.${e("tenant")}`, manage)}) then
    ${forbidden("not allowed to change this entry")}
  end if;
  if v_patch ? 'startedAt' then
    v_row.${e("startedAt")} := (v_patch ->> 'startedAt')::timestamptz;
  end if;
  if v_patch ? 'endedAt' then
    if v_patch ->> 'endedAt' is null then
      ${fail("TIME_ENTRY_INVALID", "a finished entry can't be restarted; start a timer instead", "22023")}
    end if;
    ${patchedEnd} := (v_patch ->> 'endedAt')::timestamptz;
  end if;
  if v_row.${e("startedAt")} is null or (${patchedEnd} is not null and ${patchedEnd} <= v_row.${e("startedAt")}) then
    ${fail("TIME_ENTRY_INVALID", "ended_at must be after started_at", "22023")}
  end if;${
    durationMode
      ? `
  if v_ended is not null then
    v_row.${e("seconds")} := extract(epoch from v_ended - v_row.${e("startedAt")})::bigint;
    v_row.${e("runningSince")} := null;
  end if;`
      : ""
  }
  if v_patch ? 'subjectType' or v_patch ? 'subjectId' then
    ${
      bound
        ? `${setSubject("(v_patch ->> 'subjectType')", "(v_patch ->> 'subjectId')", "    ")}
    ${subjectCheck(`v_row.${e("tenant")}`, "(v_patch ->> 'subjectType')", "(v_patch ->> 'subjectId')")}`
        : `v_row.${e("subjectType")} := v_patch ->> 'subjectType';
    v_row.${e("subjectId")} := v_patch ->> 'subjectId';
    ${subjectCheck(`v_row.${e("tenant")}`, `v_row.${e("subjectType")}`, `v_row.${e("subjectId")}`)}`
    }
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
      ${durationMode ? `${e("seconds")} = v_row.${e("seconds")}, ${e("runningSince")} = v_row.${e("runningSince")}` : `${e("endedAt")} = v_row.${e("endedAt")}`},
      ${subjectColumns.map((column) => `${column} = v_row.${column},`).join("\n      ")}
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
  if not (${SERVICE_CALLER} or (${ownedByMe("v_row")} and ${ctx.can("tenant", `v_row.${e("tenant")}`, track)}) or ${ctx.can("tenant", `v_row.${e("tenant")}`, manage)}) then
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
${employeeMode ? `${dropSignatures(fn("list_time_entries"), listTypes, false)}\n` : ""}create or replace function ${fn("list_time_entries")}(tenant ${ctx.idType}, user_id uuid default null, starts timestamptz default null, ends timestamptz default null, subject_type text default null, subject_id text default null, everyone boolean default false, page_size integer default 200${employeeMode ? ", employee_id uuid default null" : ""})
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
${
  employeeMode
    ? `  v_owner uuid := coalesce(list_time_entries.employee_id, (select y.${staff?.col("employees", "id")} from ${staff?.table("employees")} y where y.${staff?.col("employees", "tenant")} = list_time_entries.tenant and y.${staff?.col("employees", "user")} = coalesce(list_time_entries.user_id, auth.uid())));
  v_rows jsonb;
begin
  if not (${SERVICE_CALLER} or ((v_owner = ${myEmployee("list_time_entries.tenant")} and not list_time_entries.everyone) and ${ctx.can("tenant", "list_time_entries.tenant", track)}) or ${ctx.can("tenant", "list_time_entries.tenant", read)}) then`
    : `  v_user uuid := coalesce(list_time_entries.user_id, auth.uid());
  v_rows jsonb;
begin
  if not (${SERVICE_CALLER} or ((v_user = auth.uid() and not list_time_entries.everyone) and ${ctx.can("tenant", "list_time_entries.tenant", track)}) or ${ctx.can("tenant", "list_time_entries.tenant", read)}) then`
}
    ${forbidden("not allowed to read these entries")}
  end if;
  select coalesce(jsonb_agg(${entryJson("q")} order by q.${e("startedAt")} desc), '[]'::jsonb) into v_rows
  from (
    select * from ${entries} x
    where x.${e("tenant")} = list_time_entries.tenant
      and (list_time_entries.everyone or x.${eOwner} = ${employeeMode ? "v_owner" : "v_user"})
      and (list_time_entries.starts is null or coalesce(${ended("x")}, 'infinity'::timestamptz) > list_time_entries.starts)
      and (list_time_entries.ends is null or x.${e("startedAt")} < list_time_entries.ends)
      and (list_time_entries.subject_type is null or ${rowSubject("x").type} = list_time_entries.subject_type)
      and (list_time_entries.subject_id is null or ${rowSubject("x").id} = list_time_entries.subject_id)
    order by x.${e("startedAt")} desc
    limit ${pageSize("list_time_entries.page_size", 200, 1000)}
  ) q;
  return v_rows;
end;
$$;
${userGrant(`${fn("list_time_entries")}(${listTypes}${employeeMode ? ", uuid" : ""})`)}

${
  statusMode
    ? statusTimesheetFunctions(ctx, {
        entries,
        timesheets,
        e,
        t,
        read,
        track,
        manage,
        approve: ctx.permission("approve", permissions.approve),
        entryJson,
        timesheetRecord,
        forbidden,
        timesheetNotFound,
        week: (at: string, user: string) => weekOf(at, user),
        ended,
        running,
        owner: owner.status,
      })
    : approvalTimesheetFunctions(ctx, {
        entries,
        timesheets,
        ar,
        e,
        t,
        a,
        read,
        track,
        manage,
        openApproval: approvals?.fn("open_approval") ?? "",
        subject: TIMESHEET_SUBJECT,
        policy,
        entryJson,
        timesheetJson,
        timesheetRecord,
        status,
        forbidden,
        timesheetNotFound,
        weekOf,
        ended,
        running,
      })
}`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  const extra = extraFieldsArg(ctx.extraColumns("entries", RESERVED)).contract;
  const owner = byEmployee(ctx) ? ["uuid"] : [];

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
        ...owner,
        ...extra,
      ],
      returns: "jsonb",
    },
    {
      name: "submit_timesheet",
      args: ["{id}", "date", "text", ...owner],
      returns: "jsonb",
    },
    {
      name: "get_timesheet",
      args: ["{id}", "date", "uuid", ...owner],
      returns: "jsonb",
    },
  ];
}

const CONTRIBUTES: BlockContributes = {
  approvals: (own) =>
    own.flag("approvals", true)
      ? [
          {
            subject: TIMESHEET_SUBJECT,
            access: "declared",
            approve: ({ subjectId }) =>
              `perform ${own.fn("approve_timesheet")}(${subjectId}::uuid);`,
          },
        ]
      : [],
};

const REQUIRES = ["memberships", "permissions", "approvals"] as const;

export const TIME_TRACKING: BlockSqlDefinition = {
  contributes: CONTRIBUTES,
  name: "time-tracking",
  scopes: ["tenant"],
  title: "Time tracking",
  description:
    "Time entries with one running timer per member and no overlaps, on any record, billable with a rate. Weekly timesheets go through approvals, and a submitted or approved week is locked.",
  requires: [...REQUIRES],
  dependencies: (layout) =>
    layout.modules?.["time-tracking"]?.options?.["approvals"] === false
      ? REQUIRES.filter((name) => name !== "approvals")
      : [...REQUIRES],
  integrates: ["outbox", "audit", "employees"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 3,
  upgrades: [
    {
      from: 1,
      description:
        "The rate is bigint minor units per hour with a rate_currency (ADR 0037); start_timer and log_time take rate_currency.",
      sql: upgradeRateToMoney,
    },
    {
      from: 2,
      description:
        "The entry guard lets through an update that changes only employee_id, which employees keeps current.",
      sql: () => "",
    },
  ],
  names: NAMES,
  contract,
  build,
};
