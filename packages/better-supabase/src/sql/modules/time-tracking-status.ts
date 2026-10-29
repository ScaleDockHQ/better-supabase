import type { BlockSqlContext } from "../context.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { fail, pageSize, SERVICE_CALLER, userGrant } from "../shared.ts";

const WHERE = "blocks.time-tracking.options.userTimeZone";

const COLUMN = /^[a-z_][a-z0-9_]{0,62}$/u;

/** `options.userTimeZone`: the column that holds each user's time zone. */
export interface UserTimeZone {
  readonly table: string;
  readonly column: string;
  readonly key: string;
}

/**
 * `options.userTimeZone` (`{ column: "schema.table.column", key? }`), or
 * `undefined` when weeks start in `options.timeZone` for everyone.
 */
export function userTimeZoneOf(ctx: BlockSqlContext): UserTimeZone | undefined {
  const raw = ctx.option("userTimeZone");

  if (raw === undefined) {
    return undefined;
  }

  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
    throw new TypeError(
      `${WHERE} must be { column: "schema.table.column", key? }`,
    );
  }

  const entry: Readonly<Record<string, unknown>> = { ...raw };
  const column = entry["column"];
  const key = entry["key"] ?? "id";
  const parts = typeof column === "string" ? column.split(".") : [];

  if (parts.length !== 3 || !parts.every((part) => COLUMN.test(part))) {
    throw new TypeError(`${WHERE}.column must be "schema.table.column"`);
  }

  if (typeof key !== "string" || !COLUMN.test(key)) {
    throw new TypeError(`${WHERE}.key must be the column holding the user id`);
  }

  return {
    table: `${sqlIdent(parts[0]!)}.${sqlIdent(parts[1]!)}`,
    column: sqlIdent(parts[2]!),
    key: sqlIdent(key),
  };
}

/**
 * `time_week(at, user_id)`: the Monday of the week in the user's own time zone,
 * or in `options.timeZone` when the user has none.
 */
export function userWeekFunction(
  ctx: BlockSqlContext,
  zone: UserTimeZone,
  fallback: string,
): string {
  const fn = ctx.fn("time_week");

  return `
-- The Monday of the week an instant falls in for a user, in the time zone
-- options.userTimeZone names for them, else in options.timeZone.
create or replace function ${fn}(at timestamptz, user_id uuid)
returns date
language sql
stable
security definer
set search_path = ''
as $$
  select (date_trunc('week', time_week.at at time zone coalesce(
    (select nullif(p.${zone.column}::text, '') from ${zone.table} p where p.${zone.key} = time_week.user_id),
    ${fallback}
  )))::date;
$$;
${userGrant(`${fn}(timestamptz, uuid)`)}
`;
}

/** What the timesheet functions of the status mode read from the module. */
export interface StatusTimesheetNames {
  readonly entries: string;
  readonly timesheets: string;
  readonly e: (column: string) => string;
  readonly t: (column: string) => string;
  readonly read: string;
  readonly track: string;
  readonly manage: string;
  readonly approve: string;
  readonly entryJson: (row: string) => string;
  readonly timesheetRecord: (
    type: string,
    row: string,
    summary: string,
  ) => string;
  readonly forbidden: (message: string) => string;
  readonly timesheetNotFound: string;
  readonly week: (at: string, user: string) => string;
  readonly ended: (alias: string) => string;
  readonly running: (alias: string) => string;
  readonly owner: StatusTimesheetOwner;
  /** Per-employee weeks that the approvals block decides. */
  readonly approvals?: LinkedTimesheetApprovals;
}

/** The approvals block, for weeks it decides while the status column stays. */
export interface LinkedTimesheetApprovals {
  readonly open: string;
  readonly requests: string;
  readonly a: (column: string) => string;
  readonly subject: string;
  readonly policy: string;
}

export interface StatusTimesheetOwner {
  readonly employee: boolean;
  readonly entries: string;
  readonly timesheets: string;
  readonly sheetUser: boolean;
  readonly mine: (tenant: string) => string;
  readonly ofUser: (tenant: string, user: string) => string;
  readonly userOf: (employee: string) => string;
  readonly exists: (tenant: string, employee: string) => string;
  readonly json: (row: string) => string;
}

/**
 * The timesheet functions when `options.approvals` is `false`: the status
 * column holds open, submitted, approved or rejected, and members with the
 * approve permission decide instead of an approval request.
 */
export function statusTimesheetFunctions(
  ctx: BlockSqlContext,
  names: StatusTimesheetNames,
): string {
  const { entries, timesheets, e, t, read, track, manage, approve } = names;

  const { entryJson, timesheetRecord, forbidden, timesheetNotFound, week } =
    names;

  const { ended, running, owner } = names;
  const linked = names.approvals;
  const by = owner.employee;

  // Whether week row `row` has an approval request still waiting.
  const pendingApproval = (row: string): string =>
    linked === undefined
      ? "false"
      : `exists (select 1 from ${linked.requests} x where x.${linked.a("subjectType")} = ${sqlString(linked.subject)} and x.${linked.a("subjectId")} = ${row}.${t("id")}::text and x.${linked.a("status")} = 'pending')`;

  const ownerVar = by ? "v_owner" : "v_user";

  const sheetMine = (row: string): string =>
    by
      ? `(${owner.sheetUser ? `coalesce(${row}.${t("user")} = auth.uid(), false) or ` : ""}${row}.${owner.timesheets} = ${owner.mine(`${row}.${t("tenant")}`)})`
      : `coalesce(${row}.${t("user")} = auth.uid(), false)`;

  const ownerParam = by ? ", employee_id uuid default null" : "";
  const ownerType = by ? ", uuid" : "";
  const fn = (name: string): string => ctx.fn(name);

  const label = (row: string): string =>
    ctx.label("timesheets", "status", `${row}.${t("status")}`);

  const is = (row: string, labels: readonly string[]): string =>
    ctx.is("timesheets", "status", `${row}.${t("status")}`, labels);

  const value = (status: string): string =>
    ctx.value("timesheets", "status", status);

  const optional = (logical: string, row: string): string =>
    ctx.has("timesheets", logical)
      ? `, '${logical}', ${row}.${t(logical)}`
      : "";

  const json = (row: string): string =>
    `jsonb_build_object('id', ${row}.${t("id")}, 'organizationId', ${row}.${t("tenant")}, ${owner.json(row)}, 'week', ${row}.${t("week")}, 'status', ${label(row)}, 'approvalId', null, 'note', ${row}.${t("note")}, 'submittedAt', ${row}.${t("submittedAt")}, 'approvedAt', ${row}.${t("approvedAt")}, 'createdAt', ${row}.${t("createdAt")}${optional("decidedBy", row)}${optional("decidedAt", row)}${optional("decisionNote", row)})`;

  const decide = (note: string): string =>
    [
      ...(ctx.has("timesheets", "decidedBy")
        ? [`${t("decidedBy")} = auth.uid()`]
        : []),
      ...(ctx.has("timesheets", "decidedAt")
        ? [`${t("decidedAt")} = now()`]
        : []),
      ...(ctx.has("timesheets", "decisionNote")
        ? [`${t("decisionNote")} = ${note}`]
        : []),
    ]
      .map((set) => `, ${set}`)
      .join("");

  const clearDecision = (["decidedBy", "decidedAt", "decisionNote"] as const)
    .filter((logical) => ctx.has("timesheets", logical))
    .map((logical) => `, ${t(logical)} = null`)
    .join("");

  const decision = (
    name: "approve_timesheet" | "reject_timesheet",
    status: "approved" | "rejected",
    event: string,
    summary: string,
  ): string => `
create or replace function ${fn(name)}(timesheet_id uuid${name === "reject_timesheet" ? ", note text default null" : ""})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sheet ${timesheets}%rowtype;
begin
  select * into v_sheet from ${timesheets} s where s.${t("id")} = ${name}.timesheet_id for update;
  if not found then
    ${timesheetNotFound}
  end if;
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", `v_sheet.${t("tenant")}`, approve)}) then
    ${forbidden("not allowed to decide timesheets")}
  end if;
  if not ${SERVICE_CALLER} and ${sheetMine("v_sheet")} then
    ${forbidden("you can't decide your own timesheet")}
  end if;
  if not ${is("v_sheet", ["submitted"])} then
    ${fail("TIMESHEET_NOT_SUBMITTED", "only a submitted week can be decided", "55000")}
  end if;${
    linked === undefined
      ? ""
      : `
  if ${pendingApproval("v_sheet")} then
    ${fail("TIMESHEET_IN_APPROVAL", "this week is decided through its approval request", "55000")}
  end if;`
  }
  update ${timesheets} s set ${t("status")} = ${value(status)}${status === "approved" ? `, ${t("approvedAt")} = now()` : ""}${decide(name === "reject_timesheet" ? "reject_timesheet.note" : "null")}
    where s.${t("id")} = v_sheet.${t("id")}
    returning * into v_sheet;
  ${timesheetRecord(event, "v_sheet", summary)}
  return ${json("v_sheet")};
end;
$$;
${userGrant(`${fn(name)}(uuid${name === "reject_timesheet" ? ", text" : ""})`)}
`;

  return `-- One member's week: the timesheet (status open when there is none yet),
-- the entries that start in it and their totals.
${by ? `drop function if exists ${fn("get_timesheet")}(${ctx.idType}, date, uuid);\n` : ""}create or replace function ${fn("get_timesheet")}(tenant ${ctx.idType}, week date, user_id uuid default null${ownerParam})
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := coalesce(get_timesheet.user_id, auth.uid());${by ? `\n  v_owner uuid := coalesce(get_timesheet.employee_id, ${owner.ofUser("get_timesheet.tenant", "v_user")});` : ""}
  v_week date := date_trunc('week', get_timesheet.week)::date;
  v_sheet ${timesheets}%rowtype;
  v_json jsonb;
  v_entries jsonb;
  v_totals jsonb;
begin
  if not (${SERVICE_CALLER} or (${by ? `v_owner = ${owner.mine("get_timesheet.tenant")}` : "v_user = auth.uid()"} and ${ctx.can("tenant", "get_timesheet.tenant", track)}) or ${ctx.can("tenant", "get_timesheet.tenant", read)}) then
    ${forbidden("not allowed to read this timesheet")}
  end if;
  select * into v_sheet from ${timesheets} s
    where s.${t("tenant")} = get_timesheet.tenant and s.${owner.timesheets} = ${ownerVar} and s.${t("week")} = v_week;
  if found then
    v_json := ${json("v_sheet")};
  else
    v_json := jsonb_build_object('id', null, 'organizationId', get_timesheet.tenant, ${by ? `'userId', ${owner.userOf("v_owner")}, 'employeeId', v_owner` : "'userId', v_user"}, 'week', v_week, 'status', 'open');
  end if;
  select coalesce(jsonb_agg(${entryJson("x")} order by x.${e("startedAt")}), '[]'::jsonb),
    jsonb_build_object(
      'seconds', coalesce(sum(extract(epoch from coalesce(${ended("x")}, now()) - x.${e("startedAt")})), 0)::bigint,
      'billableSeconds', coalesce(sum(extract(epoch from coalesce(${ended("x")}, now()) - x.${e("startedAt")})) filter (where x.${e("billable")}), 0)::bigint,
      'amounts', (
        select coalesce(jsonb_agg(jsonb_build_object('amount', q.amount::text, 'currency', q.currency) order by q.currency), '[]'::jsonb)
        from (
          select y.${e("rateCurrency")} as currency,
            round(sum(extract(epoch from coalesce(${ended("y")}, now()) - y.${e("startedAt")}) * y.${e("rate")} / 3600))::bigint as amount
          from ${entries} y
          where y.${e("tenant")} = get_timesheet.tenant and y.${owner.entries} = ${ownerVar}
            and ${week(`y.${e("startedAt")}`, `y.${owner.entries}`)} = v_week
            and y.${e("billable")} and y.${e("rate")} is not null
          group by y.${e("rateCurrency")}
        ) q
      )
    )
    into v_entries, v_totals
  from ${entries} x
  where x.${e("tenant")} = get_timesheet.tenant and x.${owner.entries} = ${ownerVar}
    and ${week(`x.${e("startedAt")}`, `x.${owner.entries}`)} = v_week;
  return v_json || jsonb_build_object('entries', v_entries, 'totals', v_totals);
end;
$$;
${userGrant(`${fn("get_timesheet")}(${ctx.idType}, date, uuid${ownerType})`)}

-- Sends the caller's week for a decision. The week locks until a rejection.
${by ? `drop function if exists ${fn("submit_timesheet")}(${ctx.idType}, date, text);\n` : ""}create or replace function ${fn("submit_timesheet")}(tenant ${ctx.idType}, week date, note text default null${ownerParam})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_week date := date_trunc('week', submit_timesheet.week)::date;
  v_sheet ${timesheets}%rowtype;${by ? `\n  v_mine uuid := ${owner.mine("submit_timesheet.tenant")};\n  v_owner uuid := coalesce(submit_timesheet.employee_id, v_mine);` : ""}
begin
${
  by
    ? `  if v_owner is null then
    ${fail("TIME_EMPLOYEE_MISSING", "you have no employee record in this organization", "22023")}
  end if;
  if v_owner is not distinct from v_mine then
    if v_me is null or not ${ctx.can("tenant", "submit_timesheet.tenant", track)} then
      ${forbidden("not allowed to submit a timesheet here")}
    end if;
  elsif not (${SERVICE_CALLER} or ${ctx.can("tenant", "submit_timesheet.tenant", manage)}) then
    ${forbidden("not allowed to submit another employee's timesheet")}
  elsif not ${owner.exists("submit_timesheet.tenant", "v_owner")} then
    ${fail("TIME_EMPLOYEE_INVALID", "no employee record for that member in this organization", "22023")}
  end if;
  perform pg_advisory_xact_lock(hashtextextended('time_entry:' || submit_timesheet.tenant::text || ':' || v_owner::text, 0));`
    : `  if v_me is null or not ${ctx.can("tenant", "submit_timesheet.tenant", track)} then
    ${forbidden("not allowed to submit a timesheet here")}
  end if;
  perform pg_advisory_xact_lock(hashtextextended('time_entry:' || submit_timesheet.tenant::text || ':' || v_me::text, 0));`
}
  if exists (
    select 1 from ${entries} x
    where x.${e("tenant")} = submit_timesheet.tenant and x.${owner.entries} = ${by ? "v_owner" : "v_me"} and ${running("x")}
      and ${week(`x.${e("startedAt")}`, `x.${owner.entries}`)} = v_week
  ) then
    ${fail("TIMESHEET_TIMER_RUNNING", "stop the running timer before submitting this week", "55000")}
  end if;
  insert into ${timesheets} (${t("tenant")}, ${by ? `${owner.sheetUser ? `${t("user")}, ` : ""}${owner.timesheets}` : t("user")}, ${t("week")}, ${t("status")})
  values (submit_timesheet.tenant, ${by ? `${owner.sheetUser ? `${owner.userOf("v_owner")}, ` : ""}v_owner` : "v_me"}, v_week, ${value("open")})
  on conflict (${t("tenant")}, ${owner.timesheets}, ${t("week")}) do nothing;
  select * into v_sheet from ${timesheets} s
    where s.${t("tenant")} = submit_timesheet.tenant and s.${owner.timesheets} = ${by ? "v_owner" : "v_me"} and s.${t("week")} = v_week
    for update;
  if ${is("v_sheet", ["approved"])} then
    ${fail("TIMESHEET_APPROVED", "this week is already approved", "55000")}
  end if;
  if ${is("v_sheet", ["submitted"])}${linked === undefined ? "" : ` and ${pendingApproval("v_sheet")}`} then
    ${fail("TIMESHEET_SUBMITTED", "this week is already waiting for a decision", "55000")}
  end if;
  ${ctx.hook("before_timesheet_submit", [
    ["uuid", `v_sheet.${t("id")}`],
    [ctx.idType, "submit_timesheet.tenant"],
    ["date", "v_week"],
  ])}
  update ${timesheets} s
  set ${t("status")} = ${value("submitted")}, ${t("note")} = submit_timesheet.note, ${t("submittedAt")} = now()${clearDecision}
  where s.${t("id")} = v_sheet.${t("id")}
  returning * into v_sheet;${
    linked === undefined
      ? ""
      : `
  perform ${linked.open}(
    submit_timesheet.tenant, ${sqlString(linked.subject)}, v_sheet.${t("id")}::text, 'approve',
    ${sqlString(linked.policy)}::jsonb || jsonb_build_object('managerOf', v_owner::text), submit_timesheet.note,
    jsonb_build_object('userId', ${owner.userOf("v_owner")}, 'employeeId', v_owner, 'week', v_week),
    ${owner.userOf("v_owner")}
  );`
  }
  ${timesheetRecord("timesheet.submitted", "v_sheet", "submitted a timesheet")}
  ${ctx.hook("after_timesheet_submit", [["uuid", `v_sheet.${t("id")}`]])}
  return ${json("v_sheet")};
end;
$$;
${userGrant(`${fn("submit_timesheet")}(${ctx.idType}, date, text${ownerType})`)}

drop function if exists ${fn("approve_timesheet")}(uuid);
${decision("approve_timesheet", "approved", "timesheet.approved", "approved a timesheet")}${
    linked === undefined
      ? ""
      : `
-- Applies the final decision of a week's approval request: approvals calls it,
-- with the user who decided. It isn't granted to anyone.
create or replace function ${fn("timesheet_approval_decided")}(timesheet_id uuid, approved boolean, note text, decided_by uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sheet ${timesheets}%rowtype;
begin
  update ${timesheets} s set ${t("status")} = case when timesheet_approval_decided.approved then ${value("approved")} else ${value("rejected")} end,
    ${t("approvedAt")} = case when timesheet_approval_decided.approved then now() end${[
      ...(ctx.has("timesheets", "decidedBy")
        ? [`${t("decidedBy")} = timesheet_approval_decided.decided_by`]
        : []),
      ...(ctx.has("timesheets", "decidedAt")
        ? [`${t("decidedAt")} = now()`]
        : []),
      ...(ctx.has("timesheets", "decisionNote")
        ? [`${t("decisionNote")} = timesheet_approval_decided.note`]
        : []),
    ]
      .map((set) => `, ${set}`)
      .join("")}
    where s.${t("id")} = timesheet_approval_decided.timesheet_id and ${is("s", ["submitted"])}
    returning * into v_sheet;
  if not found then
    return;
  end if;
  if timesheet_approval_decided.approved then
    ${timesheetRecord("timesheet.approved", "v_sheet", "approved a timesheet")}
  else
    ${timesheetRecord("timesheet.rejected", "v_sheet", "rejected a timesheet")}
  end if;
end;
$$;
revoke execute on function ${fn("timesheet_approval_decided")}(uuid, boolean, text, uuid) from public, anon, authenticated;
`
  }${decision("reject_timesheet", "rejected", "timesheet.rejected", "rejected a timesheet")}
-- Unlocks an approved or rejected week so its entries can change and it can
-- be sent again.
create or replace function ${fn("reopen_timesheet")}(timesheet_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sheet ${timesheets}%rowtype;
begin
  select * into v_sheet from ${timesheets} s where s.${t("id")} = reopen_timesheet.timesheet_id for update;
  if not found then
    ${timesheetNotFound}
  end if;
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", `v_sheet.${t("tenant")}`, manage)}) then
    ${forbidden("not allowed to reopen timesheets")}
  end if;
  if not ${is("v_sheet", ["approved", "rejected"])} then
    ${fail("TIMESHEET_NOT_APPROVED", "only an approved or rejected week can be reopened", "55000")}
  end if;
  update ${timesheets} s set ${t("status")} = ${value("open")}, ${t("approvedAt")} = null, ${t("submittedAt")} = null${clearDecision}
    where s.${t("id")} = v_sheet.${t("id")}
    returning * into v_sheet;
  ${timesheetRecord("timesheet.reopened", "v_sheet", "reopened a timesheet")}
  return ${json("v_sheet")};
end;
$$;
${userGrant(`${fn("reopen_timesheet")}(uuid)`)}

-- Newest week first: the caller's timesheets, or everyone's with the read permission.
${by ? `drop function if exists ${fn("list_timesheets")}(${ctx.idType}, uuid, text, integer, date);\n` : ""}create or replace function ${fn("list_timesheets")}(tenant ${ctx.idType}, user_id uuid default null, status text default null, page_size integer default 50, before date default null${ownerParam})
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
  if not v_reader and list_timesheets.user_id is not null and list_timesheets.user_id is distinct from auth.uid() then
    ${forbidden("not allowed to read another member's timesheets")}
  end if;${
    by
      ? `
  if not v_reader and list_timesheets.employee_id is not null and list_timesheets.employee_id is distinct from ${owner.mine("list_timesheets.tenant")} then
    ${forbidden("not allowed to read another employee's timesheets")}
  end if;`
      : ""
  }
  select coalesce(jsonb_agg(q.item order by q.week desc, q.created desc), '[]'::jsonb) into v_rows
  from (
    select ${json("s")} as item, s.${t("week")} as week, s.${t("createdAt")} as created
    from ${timesheets} s
    where s.${t("tenant")} = list_timesheets.tenant
      and ${
        by
          ? `(case when v_reader then (list_timesheets.user_id is null or s.${owner.timesheets} = ${owner.ofUser("list_timesheets.tenant", "list_timesheets.user_id")}) and (list_timesheets.employee_id is null or s.${owner.timesheets} = list_timesheets.employee_id) else s.${owner.timesheets} = ${owner.mine("list_timesheets.tenant")} end)`
          : `(case when v_reader then list_timesheets.user_id is null or s.${t("user")} = list_timesheets.user_id else s.${t("user")} = auth.uid() end)`
      }
      and (list_timesheets.status is null or ${label("s")} = list_timesheets.status)
      and (list_timesheets.before is null or s.${t("week")} < list_timesheets.before)
    order by s.${t("week")} desc, s.${t("createdAt")} desc
    limit ${pageSize("list_timesheets.page_size", 50, 200)}
  ) q;
  return v_rows;
end;
$$;
${userGrant(`${fn("list_timesheets")}(${ctx.idType}, uuid, text, integer, date${ownerType})`)}
`;
}
