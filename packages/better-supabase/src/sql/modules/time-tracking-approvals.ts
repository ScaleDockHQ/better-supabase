import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { fail, pageSize, SERVICE_CALLER, userGrant } from "../shared.ts";

/** What the approvals-mode timesheet functions read from the module. */
export interface ApprovalTimesheetNames {
  readonly entries: string;
  readonly timesheets: string;
  readonly ar: string;
  readonly e: (column: string) => string;
  readonly t: (column: string) => string;
  readonly a: (column: string) => string;
  readonly read: string;
  readonly track: string;
  readonly manage: string;
  readonly openApproval: string;
  readonly subject: string;
  readonly policy: string;
  readonly entryJson: (row: string) => string;
  readonly timesheetJson: (row: string, approval: string) => string;
  readonly timesheetRecord: (
    type: string,
    row: string,
    summary: string,
  ) => string;
  readonly status: (row: string, approval: string) => string;
  readonly forbidden: (message: string) => string;
  readonly timesheetNotFound: string;
  readonly weekOf: (at: string, user: string) => string;
  readonly ended: (alias: string) => string;
  readonly running: (alias: string) => string;
}

/**
 * The timesheet functions when weeks go through the approvals block: a
 * submitted week opens an approval request, and the final approval locks it.
 */
export function approvalTimesheetFunctions(
  ctx: BlockSqlContext,
  names: ApprovalTimesheetNames,
): string {
  const { entries, timesheets, ar, e, t, a, read, track, manage } = names;

  const { entryJson, timesheetJson, timesheetRecord, status, forbidden } =
    names;

  const { timesheetNotFound, weekOf, ended, running, policy } = names;
  const fn = (name: string): string => ctx.fn(name);

  return `-- One member's week: the timesheet (status open when there is none yet),
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
      'seconds', coalesce(sum(extract(epoch from coalesce(${ended("x")}, now()) - x.${e("startedAt")})), 0)::bigint,
      'billableSeconds', coalesce(sum(extract(epoch from coalesce(${ended("x")}, now()) - x.${e("startedAt")})) filter (where x.${e("billable")}), 0)::bigint,
      -- Billable hours times the rate, per currency, rounded to minor units.
      'amounts', (
        select coalesce(jsonb_agg(jsonb_build_object('amount', q.amount::text, 'currency', q.currency) order by q.currency), '[]'::jsonb)
        from (
          select y.${e("rateCurrency")} as currency,
            round(sum(extract(epoch from coalesce(${ended("y")}, now()) - y.${e("startedAt")}) * y.${e("rate")} / 3600))::bigint as amount
          from ${entries} y
          where y.${e("tenant")} = get_timesheet.tenant and y.${e("user")} = v_user
            and ${weekOf(`y.${e("startedAt")}`, `y.${e("user")}`)} = v_week
            and y.${e("billable")} and y.${e("rate")} is not null
          group by y.${e("rateCurrency")}
        ) q
      )
    )
    into v_entries, v_totals
  from ${entries} x
  where x.${e("tenant")} = get_timesheet.tenant and x.${e("user")} = v_user
    and ${weekOf(`x.${e("startedAt")}`, `x.${e("user")}`)} = v_week;
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
    where x.${e("tenant")} = submit_timesheet.tenant and x.${e("user")} = v_me and ${running("x")}
      and ${weekOf(`x.${e("startedAt")}`, `x.${e("user")}`)} = v_week
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
  select coalesce(sum(extract(epoch from ${ended("x")} - x.${e("startedAt")})), 0)::bigint into v_seconds
    from ${entries} x
    where x.${e("tenant")} = submit_timesheet.tenant and x.${e("user")} = v_me
      and ${weekOf(`x.${e("startedAt")}`, `x.${e("user")}`)} = v_week;
  v_request := ${names.openApproval}(
    submit_timesheet.tenant, ${sqlString(names.subject)}, v_sheet.${t("id")}::text, 'approve',
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
