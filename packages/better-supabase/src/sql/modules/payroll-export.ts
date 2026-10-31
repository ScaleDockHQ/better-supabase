import type { PayrollExportEvents } from "../../blocks/payroll-export/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  fail,
  lockTable,
  SERVICE_CALLER,
  schemaPreamble,
  userGrant,
} from "../shared.ts";
import { leaveTypeKey } from "./leave-feed.ts";
import { leaveByEmployee } from "./leave-owner.ts";
import { OPERATIONS } from "./permissions-model.ts";
import { byEmployee, entryEnded } from "./time-tracking-owner.ts";

const WHERE = "blocks.payroll-export.options";

/** Where a payroll run stands: `exported` locks its lines. */
export const PAYROLL_RUN_STATUSES = ["draft", "exported"] as const;

/** What a payroll line counts. */
export const PAYROLL_LINE_KINDS = ["worked", "leave", "scheduled"] as const;

/** The unit of a payroll line's quantity. */
export const PAYROLL_LINE_UNITS = ["hours", "days"] as const;

/** The blocks a run can read lines from. */
const PAYROLL_SOURCES = ["time-tracking", "leave", "shifts"] as const;

/**
 * `options.sources` when the app names none. Shifts are opt-in: scheduled hours
 * overlap worked hours.
 */
const DEFAULT_PAYROLL_SOURCES: readonly string[] = ["time-tracking", "leave"];

const EVENTS: BlockSqlEvents<PayrollExportEvents> = {
  "payroll_run.created": {
    subject: "payroll-runs",
    payload: [
      "organizationId",
      "id",
      "periodFrom",
      "periodTo",
      "status",
      "lineCount",
    ],
  },
  "payroll_run.exported": {
    subject: "payroll-runs",
    payload: [
      "organizationId",
      "id",
      "periodFrom",
      "periodTo",
      "status",
      "lineCount",
      "format",
      "checksum",
    ],
  },
};

const NAMES: BlockSqlNames = {
  entities: {
    payroll_run: { table: "runs", singular: "payroll_run", primary: true },
    payroll_line: { table: "lines", singular: "payroll_line" },
  },
  events: EVENTS,
  hooks: [],
  options: ["timeZone", "sources"],
  tables: {
    runs: {
      name: "payroll_runs",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        periodFrom: "period_from",
        periodTo: "period_to",
        label: "label",
        status: "status",
        format: "format",
        checksum: "checksum",
        exportedAt: "exported_at",
        exportedBy: "exported_by",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    lines: {
      name: "payroll_lines",
      app: {},
      lifecycle: { tenant: "tenant", user: "user", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        run: "run_id",
        user: "user_id",
        employee: "employee_id",
        employeeName: "employee_name",
        kind: "kind",
        code: "code",
        paid: "paid",
        unit: "unit",
        quantity: "quantity",
        sourceCount: "source_count",
        createdAt: "created_at",
      },
    },
  },
};

/** A block the collection reads, when it's there and managed. */
function linked(
  ctx: BlockSqlContext,
  module: string,
): BlockSqlContext | undefined {
  return ctx.installed(module) && ctx.of(module).mode !== "custom"
    ? ctx.of(module)
    : undefined;
}

function timeZoneOf(ctx: BlockSqlContext): string {
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

function sourcesOf(ctx: BlockSqlContext): ReadonlySet<string> {
  const given = ctx.option("sources");

  if (given === undefined) {
    return new Set(
      DEFAULT_PAYROLL_SOURCES.filter((name) => ctx.installed(name)),
    );
  }

  const raw = given;

  if (!Array.isArray(raw)) {
    throw new TypeError(`${WHERE}.sources must be a list of block names`);
  }

  const known: readonly unknown[] = PAYROLL_SOURCES;

  for (const source of raw) {
    if (!known.includes(source)) {
      throw new TypeError(
        `${WHERE}.sources: "${String(source)}" is not a source; use ${PAYROLL_SOURCES.join(", ")}`,
      );
    }
  }

  return new Set(raw.map(String));
}

/** The hours of worked time per person, from `time-tracking`. */
function timeSource(
  ctx: BlockSqlContext,
  time: BlockSqlContext,
  zone: string,
): string {
  const e = (column: string): string => time.col("entries", column);
  const employee = byEmployee(time);
  const ended = entryEnded(time, "x");

  const who = employee
    ? `x.${e("user")}, x.${e("employee")}`
    : `x.${e("user")}`;

  const l = (column: string): string => ctx.col("lines", column);

  return `
  insert into ${ctx.table("lines")} (${l("tenant")}, ${l("run")}, ${l("user")}, ${l("employee")}, ${l("kind")}, ${l("unit")}, ${l("quantity")}, ${l("sourceCount")})
  select v_run.${ctx.col("runs", "tenant")}, v_run.${ctx.col("runs", "id")}, x.${e("user")}, ${employee ? `x.${e("employee")}` : "null::uuid"},
    'worked', 'hours', round(sum(extract(epoch from ${ended} - x.${e("startedAt")}))::numeric / 3600, 2), count(*)
  from ${time.table("entries")} x
  where x.${e("tenant")} = v_run.${ctx.col("runs", "tenant")}
    and ${ended} is not null
    and ${employee ? `coalesce(x.${e("user")}, x.${e("employee")})` : `x.${e("user")}`} is not null
    and (x.${e("startedAt")} at time zone ${sqlString(zone)})::date between v_run.${ctx.col("runs", "periodFrom")} and v_run.${ctx.col("runs", "periodTo")}
  group by ${who}
  having sum(extract(epoch from ${ended} - x.${e("startedAt")})) > 0;
  get diagnostics v_added = row_count;
  v_count := v_count + v_added;`;
}

/** The days or hours of approved leave per person and type, from `leave`. */
function leaveSource(ctx: BlockSqlContext, leave: BlockSqlContext): string {
  const q = (column: string): string => leave.col("requests", column);
  const t = (column: string): string => leave.col("types", column);
  const employee = leaveByEmployee(leave);
  const user = leave.has("requests", "user");
  const key = leaveTypeKey(leave, "t");
  const unit = leave.label("types", "unit", `t.${t("unit")}`);
  const userSql = user ? `q.${q("user")}` : "null::uuid";
  const employeeSql = employee ? `q.${q("employee")}` : "null::uuid";
  const l = (column: string): string => ctx.col("lines", column);

  const who = [user ? userSql : "", employee ? employeeSql : ""].filter(
    Boolean,
  );

  return `
  insert into ${ctx.table("lines")} (${l("tenant")}, ${l("run")}, ${l("user")}, ${l("employee")}, ${l("kind")}, ${l("code")}, ${l("paid")}, ${l("unit")}, ${l("quantity")}, ${l("sourceCount")})
  select v_run.${ctx.col("runs", "tenant")}, v_run.${ctx.col("runs", "id")}, ${userSql}, ${employeeSql}, 'leave', ${key}, t.${t("paid")},
    case when ${unit} = 'hours' then 'hours' else 'days' end, sum(q.${q("amount")}), count(*)
  from ${leave.table("requests")} q
  join ${leave.table("types")} t on t.${t("id")} = q.${q("type")}
  where q.${q("tenant")} = v_run.${ctx.col("runs", "tenant")}
    and q.${q("approvedAt")} is not null and q.${q("cancelledAt")} is null
    and q.${q("startsOn")} between v_run.${ctx.col("runs", "periodFrom")} and v_run.${ctx.col("runs", "periodTo")}
  group by ${who.join(", ")}, ${key}, t.${t("paid")}, t.${t("unit")};
  get diagnostics v_added = row_count;
  v_count := v_count + v_added;`;
}

/**
 * The hours of published, assigned shifts per person, less breaks, from
 * `shifts`.
 */
function shiftSource(
  ctx: BlockSqlContext,
  shifts: BlockSqlContext,
  zone: string,
): string {
  const a = (column: string): string => shifts.col("assignments", column);
  const s = (column: string): string => shifts.col("shifts", column);
  const l = (column: string): string => ctx.col("lines", column);

  return `
  insert into ${ctx.table("lines")} (${l("tenant")}, ${l("run")}, ${l("user")}, ${l("kind")}, ${l("unit")}, ${l("quantity")}, ${l("sourceCount")})
  select v_run.${ctx.col("runs", "tenant")}, v_run.${ctx.col("runs", "id")}, a.${a("user")}, 'scheduled', 'hours',
    round(sum(extract(epoch from a.${a("endsAt")} - a.${a("startsAt")}) / 3600.0 - s.${s("breakMinutes")} / 60.0)::numeric, 2), count(*)
  from ${shifts.table("assignments")} a
  join ${shifts.table("shifts")} s on s.${s("id")} = a.${a("shift")}
  where a.${a("tenant")} = v_run.${ctx.col("runs", "tenant")}
    and a.${a("status")} = 'assigned' and s.${s("status")} = 'published' and s.${s("canceledAt")} is null
    and (a.${a("startsAt")} at time zone ${sqlString(zone)})::date between v_run.${ctx.col("runs", "periodFrom")} and v_run.${ctx.col("runs", "periodTo")}
  group by a.${a("user")}
  having sum(extract(epoch from a.${a("endsAt")} - a.${a("startsAt")}) / 3600.0 - s.${s("breakMinutes")} / 60.0) > 0;
  get diagnostics v_added = row_count;
  v_count := v_count + v_added;`;
}

/** Fills each line's employee and name from `employees`, by employee or by user. */
function employeeNames(
  ctx: BlockSqlContext,
  employees: BlockSqlContext,
): string {
  const y = (column: string): string => employees.col("employees", column);
  const l = (column: string): string => ctx.col("lines", column);

  const name = employees.has("employees", "name")
    ? `e.${y("name")}`
    : employees.has("employees", "firstName") &&
        employees.has("employees", "lastName")
      ? `nullif(trim(concat_ws(' ', e.${y("firstName")}, e.${y("lastName")})), '')`
      : "null::text";

  return `
  update ${ctx.table("lines")} x
  set ${l("employee")} = e.${y("id")}, ${l("employeeName")} = ${name}
  from ${employees.table("employees")} e
  where x.${l("run")} = v_run.${ctx.col("runs", "id")}
    and e.${y("tenant")} = v_run.${ctx.col("runs", "tenant")}
    and (e.${y("id")} = x.${l("employee")} or (x.${l("employee")} is null and e.${y("user")} = x.${l("user")}));`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const runs = ctx.table("runs");
  const lines = ctx.table("lines");
  const r = (column: string): string => ctx.col("runs", column);
  const l = (column: string): string => ctx.col("lines", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const zone = timeZoneOf(ctx);
  const sources = sourcesOf(ctx);
  const read = ctx.permission("read", OPERATIONS["payroll-export.read"]);

  const exportKey = ctx.permission(
    "export",
    OPERATIONS["payroll-export.export"],
  );

  const time = sources.has("time-tracking")
    ? linked(ctx, "time-tracking")
    : undefined;

  const leave = sources.has("leave") ? linked(ctx, "leave") : undefined;
  const shifts = sources.has("shifts") ? linked(ctx, "shifts") : undefined;
  const employees = linked(ctx, "employees");

  for (const source of sources) {
    if (!ctx.installed(source)) {
      throw new TypeError(
        `${WHERE}.sources lists "${source}", which isn't installed; install it or take it out of sources`,
      );
    }
  }

  const name = (table: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(table).name}_${suffix}`);

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or (${tenant} is not null and ${ctx.can("tenant", tenant, permission)}))`;

  const forbidden = fail(
    "PAYROLL_FORBIDDEN",
    "not allowed to do this with payroll runs",
  );

  const invalid = (message: string): string =>
    fail("PAYROLL_RUN_INVALID", message, "22023");

  const missing = fail("PAYROLL_RUN_NOT_FOUND", "no such payroll run", "P0002");

  const lineJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${l("id")}, 'userId', ${row}.${l("user")}, 'employeeId', ${row}.${l("employee")}, 'employeeName', ${row}.${l("employeeName")}, 'kind', ${row}.${l("kind")}, 'code', ${row}.${l("code")}, 'paid', ${row}.${l("paid")}, 'unit', ${row}.${l("unit")}, 'quantity', ${row}.${l("quantity")}::text, 'sourceCount', ${row}.${l("sourceCount")})`;

  const linesOf = (row: string): string =>
    `coalesce((select jsonb_agg(${lineJson("y")} order by y.${l("employeeName")} nulls last, coalesce(y.${l("user")}, y.${l("employee")}), y.${l("kind")}, y.${l("code")} nulls first) from ${lines} y where y.${l("run")} = ${row}.${r("id")}), '[]'::jsonb)`;

  const runJson = (row: string, withLines: boolean): string =>
    `jsonb_build_object('id', ${row}.${r("id")}, 'organizationId', ${row}.${r("tenant")}, 'periodFrom', ${row}.${r("periodFrom")}, 'periodTo', ${row}.${r("periodTo")}, 'label', ${row}.${r("label")}, 'status', ${row}.${r("status")}, 'format', ${row}.${r("format")}, 'checksum', ${row}.${r("checksum")}, 'exportedAt', ${row}.${r("exportedAt")}, 'exportedBy', ${row}.${r("exportedBy")}, 'createdBy', ${row}.${r("createdBy")}, 'createdAt', ${row}.${r("createdAt")}, 'updatedAt', ${row}.${r("updatedAt")}, 'lineCount', (select count(*) from ${lines} y where y.${l("run")} = ${row}.${r("id")})${withLines ? `, 'lines', ${linesOf(row)}` : ""})`;

  const record = (
    type: "payroll_run.created" | "payroll_run.exported",
    summary: string,
    extra = "",
  ): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', v_run.${r("tenant")}, 'id', v_run.${r("id")}, 'periodFrom', v_run.${r("periodFrom")}, 'periodTo', v_run.${r("periodTo")}, 'status', v_run.${r("status")}, 'lineCount', (select count(*) from ${lines} y where y.${l("run")} = v_run.${r("id")})${extra})`,
      subject: `'payroll-runs/' || v_run.${r("id")}::text`,
      tenant: `v_run.${r("tenant")}`,
      audit: {
        category: "data",
        targetType: "payroll_run",
        recordId: `v_run.${r("id")}::text`,
        targetLabel: `v_run.${r("periodFrom")}::text || ' to ' || v_run.${r("periodTo")}::text`,
        summary: sqlString(summary),
      },
    });

  const readPolicy = (table: string, tenant: string): string =>
    renderPolicy(
      makePolicy({
        table: ctx.table(table),
        name: name(table, "read"),
        command: "select",
        roles: ["authenticated"],
        using: ctx.scope.check(tenant, read),
      }),
      { drop: true, target: ctx.table(table) },
    );

  const overlap = (exclude: string): string => `exists (
    select 1 from ${runs} y
    where y.${r("tenant")} = v_run.${r("tenant")} and y.${r("status")} = 'exported'${exclude}
      and y.${r("periodFrom")} <= v_run.${r("periodTo")} and y.${r("periodTo")} >= v_run.${r("periodFrom")}
  )`;

  const overlapRefusal = fail(
    "PAYROLL_PERIOD_EXPORTED",
    "an exported payroll run already covers part of this period",
    "55000",
  );

  const loadRun = (arg: string, permission: string, lock: boolean): string => `
  select * into v_run from ${runs} x where x.${r("id")} = ${arg}${lock ? " for update" : ""};
  if not found then
    ${missing}
  end if;
  if not ${allowed(`v_run.${r("tenant")}`, permission)} then
    ${forbidden}
  end if;`;

  const draftOnly = (action: string): string => `
  if v_run.${r("status")} <> 'draft' then
    ${fail("PAYROLL_RUN_EXPORTED", `an exported payroll run can't be ${action}`, "55000")}
  end if;`;

  return `${schemaPreamble(ctx)}
-- Payroll runs per organization: one run collects the hours worked, the
-- approved leave and optionally the scheduled shifts of a period into lines per
-- person. A PayrollExportFormat renders the lines in TypeScript; exporting
-- locks the run and keeps the checksum of the file.
create table if not exists ${runs} (
  ${r("id")} uuid primary key default gen_random_uuid(),
  ${r("tenant")} ${idType} not null,
  ${r("periodFrom")} date not null,
  ${r("periodTo")} date not null,
  ${r("label")} text check (${r("label")} is null or length(${r("label")}) between 1 and 200),
  ${r("status")} text not null default 'draft' check (${r("status")} in ('draft', 'exported')),
  ${r("format")} text check (${r("format")} is null or length(${r("format")}) between 1 and 100),
  -- The hex SHA-256 of the exported file.
  ${r("checksum")} text check (${r("checksum")} is null or ${r("checksum")} ~ '^[0-9a-f]{64}$'),
  ${r("exportedAt")} timestamptz,
  ${r("exportedBy")} uuid,
  ${r("createdBy")} uuid,
  ${r("createdAt")} timestamptz not null default now(),
  ${r("updatedAt")} timestamptz not null default now(),
  unique (${r("tenant")}, ${r("id")}),
  check (${r("periodFrom")} <= ${r("periodTo")}),
  check (${r("periodTo")} - ${r("periodFrom")} <= 400),
  check ((${r("status")} = 'exported') = (${r("exportedAt")} is not null and ${r("format")} is not null and ${r("checksum")} is not null))
);
create index if not exists ${name("runs", "tenant_idx")} on ${runs} (${r("tenant")}, ${r("periodFrom")} desc);
${lockTable(runs, { read: true })}
${readPolicy("runs", r("tenant"))}

create table if not exists ${lines} (
  ${l("id")} uuid primary key default gen_random_uuid(),
  ${l("tenant")} ${idType} not null,
  ${l("run")} uuid not null,
  ${l("user")} uuid,
  ${l("employee")} uuid,
  -- The name when the run was collected, so an exported file stays reproducible.
  ${l("employeeName")} text,
  ${l("kind")} text not null check (${l("kind")} in ('worked', 'leave', 'scheduled')),
  -- The leave type's key; null for worked and scheduled time.
  ${l("code")} text check (${l("code")} is null or length(${l("code")}) between 1 and 200),
  ${l("paid")} boolean not null default true,
  ${l("unit")} text not null check (${l("unit")} in ('hours', 'days')),
  ${l("quantity")} numeric(12, 2) not null check (${l("quantity")} >= 0),
  -- How many entries, requests or assignments the line adds up.
  ${l("sourceCount")} integer not null default 1 check (${l("sourceCount")} >= 0),
  ${l("createdAt")} timestamptz not null default now(),
  check (${l("user")} is not null or ${l("employee")} is not null),
  foreign key (${l("tenant")}, ${l("run")}) references ${runs} (${r("tenant")}, ${r("id")}) on delete cascade
);
create unique index if not exists ${name("lines", "person_key")} on ${lines} (${l("run")}, coalesce(${l("user")}, ${l("employee")}), ${l("kind")}, coalesce(${l("code")}, ''));
create index if not exists ${name("lines", "run_idx")} on ${lines} (${l("run")});
${lockTable(lines, { read: true })}
${readPolicy("lines", l("tenant"))}

-- Rebuilds the lines of a draft run from the sources in options.sources.
create or replace function ${fn("collect_payroll_lines")}(run_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run ${runs}%rowtype;
  v_added integer;
  v_count integer := 0;
begin
  select * into v_run from ${runs} x where x.${r("id")} = collect_payroll_lines.run_id;
  delete from ${lines} where ${l("run")} = v_run.${r("id")};${time ? timeSource(ctx, time, zone) : ""}${leave ? leaveSource(ctx, leave) : ""}${shifts ? shiftSource(ctx, shifts, zone) : ""}${employees ? employeeNames(ctx, employees) : ""}
  return v_count;
end;
$$;
revoke execute on function ${fn("collect_payroll_lines")}(uuid) from public, anon, authenticated;

-- Creates a draft run for { from, to, label } (dates as YYYY-MM-DD, at most 400
-- days) and collects its lines. A period an exported run already covers is
-- refused, so nobody is paid twice for the same days.
create or replace function ${fn("create_payroll_run")}(tenant ${idType}, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run ${runs}%rowtype;
begin
  if not ${allowed("create_payroll_run.tenant", exportKey)} then
    ${forbidden}
  end if;
  if jsonb_typeof(create_payroll_run.input) is distinct from 'object'
    or coalesce(create_payroll_run.input ->> 'from', '') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
    or coalesce(create_payroll_run.input ->> 'to', '') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
    ${invalid("a payroll run has a from and a to date as YYYY-MM-DD")}
  end if;
  v_run.${r("tenant")} := create_payroll_run.tenant;
  v_run.${r("periodFrom")} := (create_payroll_run.input ->> 'from')::date;
  v_run.${r("periodTo")} := (create_payroll_run.input ->> 'to')::date;
  if ${overlap("")} then
    ${overlapRefusal}
  end if;
  insert into ${runs} (${r("tenant")}, ${r("periodFrom")}, ${r("periodTo")}, ${r("label")}, ${r("createdBy")})
  values (v_run.${r("tenant")}, v_run.${r("periodFrom")}, v_run.${r("periodTo")}, nullif(trim(create_payroll_run.input ->> 'label'), ''), auth.uid())
  returning * into v_run;
  perform ${fn("collect_payroll_lines")}(v_run.${r("id")});
  ${record("payroll_run.created", "Payroll run created")}
  return ${runJson("v_run", true)};
exception
  when check_violation then
    ${invalid("the period ends on or after it starts and covers at most 400 days; a label has 1 to 200 characters")}
  when datetime_field_overflow or invalid_datetime_format then
    ${invalid("from and to must be real dates")}
end;
$$;
${userGrant(`${fn("create_payroll_run")}(${idType}, jsonb)`)}

-- Collects the lines of a draft run again, for time that changed since.
create or replace function ${fn("refresh_payroll_run")}(run_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run ${runs}%rowtype;
begin${loadRun("refresh_payroll_run.run_id", exportKey, true)}${draftOnly("refreshed")}
  perform ${fn("collect_payroll_lines")}(v_run.${r("id")});
  update ${runs} x set ${r("updatedAt")} = now() where x.${r("id")} = v_run.${r("id")} returning * into v_run;
  return ${runJson("v_run", true)};
end;
$$;
${userGrant(`${fn("refresh_payroll_run")}(uuid)`)}

-- A run with its lines, or null when it doesn't exist or isn't visible.
create or replace function ${fn("get_payroll_run")}(run_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run ${runs}%rowtype;
begin
  select * into v_run from ${runs} x where x.${r("id")} = get_payroll_run.run_id;
  if not found or not ${allowed(`v_run.${r("tenant")}`, read)} then
    return null;
  end if;
  return ${runJson("v_run", true)};
end;
$$;
${userGrant(`${fn("get_payroll_run")}(uuid)`)}

-- The organization's runs, newest period first, without their lines.
create or replace function ${fn("list_payroll_runs")}(tenant ${idType})
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ${allowed("list_payroll_runs.tenant", read)} then
    ${forbidden}
  end if;
  return coalesce((
    select jsonb_agg(${runJson("x", false)} order by x.${r("periodFrom")} desc, x.${r("createdAt")} desc)
    from ${runs} x
    where x.${r("tenant")} = list_payroll_runs.tenant
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_payroll_runs")}(${idType})`)}

-- Locks a draft run after its file was rendered: keeps the format and the
-- SHA-256 of the file. Exporting the same file again returns the run.
create or replace function ${fn("mark_payroll_run_exported")}(run_id uuid, format text, checksum text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run ${runs}%rowtype;
begin${loadRun("mark_payroll_run_exported.run_id", exportKey, true)}
  if mark_payroll_run_exported.checksum !~ '^[0-9a-f]{64}$'
    or length(coalesce(mark_payroll_run_exported.format, '')) not between 1 and 100 then
    ${invalid("an export has a format name and the hex SHA-256 of its file")}
  end if;
  if v_run.${r("status")} = 'exported' then
    if v_run.${r("format")} = mark_payroll_run_exported.format and v_run.${r("checksum")} = mark_payroll_run_exported.checksum then
      return ${runJson("v_run", true)};
    end if;${draftOnly("exported again with a different file")}
  end if;
  if ${overlap(`\n      and y.${r("id")} <> v_run.${r("id")}`)} then
    ${overlapRefusal}
  end if;
  update ${runs} x set
    ${r("status")} = 'exported',
    ${r("format")} = mark_payroll_run_exported.format,
    ${r("checksum")} = mark_payroll_run_exported.checksum,
    ${r("exportedAt")} = now(),
    ${r("exportedBy")} = auth.uid(),
    ${r("updatedAt")} = now()
  where x.${r("id")} = v_run.${r("id")}
  returning * into v_run;
  ${record("payroll_run.exported", "Payroll run exported", `, 'format', v_run.${r("format")}, 'checksum', v_run.${r("checksum")}`)}
  return ${runJson("v_run", true)};
end;
$$;
${userGrant(`${fn("mark_payroll_run_exported")}(uuid, text, text)`)}

-- Deletes a draft run and its lines.
create or replace function ${fn("delete_payroll_run")}(run_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run ${runs}%rowtype;
begin${loadRun("delete_payroll_run.run_id", exportKey, true)}${draftOnly("deleted")}
  delete from ${runs} x where x.${r("id")} = v_run.${r("id")};
end;
$$;
${userGrant(`${fn("delete_payroll_run")}(uuid)`)}
`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    { name: "create_payroll_run", args: ["{id}", "jsonb"], returns: "jsonb" },
    { name: "refresh_payroll_run", args: ["uuid"], returns: "jsonb" },
    { name: "get_payroll_run", args: ["uuid"], returns: "jsonb" },
    { name: "list_payroll_runs", args: ["{id}"], returns: "jsonb" },
    {
      name: "mark_payroll_run_exported",
      args: ["uuid", "text", "text"],
      returns: "jsonb",
    },
    { name: "delete_payroll_run", args: ["uuid"], returns: "void" },
  ];
}

export const PAYROLL_EXPORT: BlockSqlDefinition = {
  name: "payroll-export",
  scopes: ["tenant"],
  title: "Payroll export",
  description:
    "Payroll runs that collect the hours worked, the approved leave and optionally the scheduled shifts of a period into lines per person, locked by an export through a versioned PayrollExportFormat port.",
  requires: ["memberships", "permissions"],
  integrates: [
    "time-tracking",
    "leave",
    "shifts",
    "employees",
    "outbox",
    "audit",
  ],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
};
