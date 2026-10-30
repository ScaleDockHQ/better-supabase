import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import {
  activeMembership,
  fail,
  SERVICE_CALLER,
  userGrant,
} from "../shared.ts";
import { moduleOperations } from "./permissions-model.ts";
import {
  assignmentJson,
  assignmentRecord,
  minRestHours,
  notifyShift,
  qualificationCheck,
  shiftTimeZone,
  swapJson,
} from "./shifts-shared.ts";

/**
 * Whether user `user` has approved leave on a day of shift `shift` (a shifts
 * row), or undefined without the leave block.
 */
function onLeave(
  ctx: BlockSqlContext,
  shift: string,
  user: string,
): string | undefined {
  if (!ctx.installed("leave")) {
    return undefined;
  }

  const leave = ctx.of("leave");
  const r = (column: string): string => `r.${leave.col("requests", column)}`;
  const s = (column: string): string => `${shift}.${ctx.col("shifts", column)}`;
  const zone = sqlString(shiftTimeZone(ctx));
  const owners: string[] = [];

  if (leave.has("requests", "user")) {
    owners.push(`${r("user")} = ${user}`);
  }

  if (leave.has("requests", "employee") && ctx.installed("employees")) {
    const employees = ctx.of("employees");
    const e = (column: string): string => employees.col("employees", column);

    owners.push(
      `exists (select 1 from ${employees.table("employees")} e where e.${e("id")} = ${r("employee")} and e.${e("user")} = ${user})`,
    );
  }

  if (owners.length === 0) {
    return undefined;
  }

  return `exists (
    select 1 from ${leave.table("requests")} r
    where ${r("tenant")} = ${s("tenant")}
      and (${owners.join(" or ")})
      and ${r("approvedAt")} is not null and ${r("cancelledAt")} is null
      and ${r("startsOn")} <= ((${s("endsAt")} - interval '1 microsecond') at time zone ${zone})::date
      and ${r("endsOn")} >= (${s("startsAt")} at time zone ${zone})::date
  )`;
}

/** The assignment, open shift request and swap functions. */
export function shiftAssignmentFunctions(ctx: BlockSqlContext): string {
  const shifts = ctx.table("shifts");
  const assignments = ctx.table("assignments");
  const swaps = ctx.table("swaps");
  const s = (column: string): string => ctx.col("shifts", column);
  const a = (column: string): string => ctx.col("assignments", column);
  const w = (column: string): string => ctx.col("swaps", column);
  const fn = (name: string): string => ctx.fn(name);
  const permissions = moduleOperations("shifts");
  const write = ctx.permission("write", permissions.write);
  const request = ctx.permission("request", permissions.request);
  const manage = ctx.permission("manage", permissions.manage);
  const members = ctx.of("memberships");
  const m = (column: string): string => members.col("memberships", column);
  const zone = sqlString(shiftTimeZone(ctx));
  const rest = minRestHours(ctx);
  const warnOnly = qualificationCheck(ctx) === "warn";
  const check = fn("shift_assignment_check");

  const has = (table: string, column: string): boolean =>
    ctx.has(table, column);

  const insertCol = (table: string, column: string): string =>
    has(table, column) ? `, ${ctx.col(table, column)}` : "";

  const insertVal = (table: string, column: string, value: string): string =>
    has(table, column) ? `, ${value}` : "";

  const touch = (table: string): string =>
    has(table, "updatedAt") ? `, ${ctx.col(table, "updatedAt")} = now()` : "";

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or ${ctx.can("tenant", tenant, permission)})`;

  const forbidden = (message: string): string =>
    fail("SHIFT_FORBIDDEN", message);

  const assignmentInvalid = (message: string): string =>
    fail("SHIFT_ASSIGNMENT_INVALID", message, "22023");

  const swapInvalid = (message: string): string =>
    fail("SHIFT_SWAP_INVALID", message, "22023");

  const shiftNotFound = fail("SHIFT_NOT_FOUND", "shift not found", "P0002");

  const assignmentNotFound = fail(
    "SHIFT_ASSIGNMENT_NOT_FOUND",
    "shift assignment not found",
    "P0002",
  );

  const isMember = (tenant: string, user: string): string =>
    `exists (select 1 from ${members.table("memberships")} mm where mm.${m("tenant")} = ${tenant} and mm.${m("user")} = ${user}${activeMembership(members, "mm")})`;

  const leave = onLeave(ctx, "v_shift", "shift_assignment_check.user_id");

  const leaveCheck =
    leave === undefined
      ? ""
      : `
  if ${leave} then
    ${fail("SHIFT_ASSIGNMENT_ON_LEAVE", "the member has approved leave on the shift's day", "23P01")}
  end if;`;

  const qualifications = ctx.installed("qualifications")
    ? ctx.of("qualifications")
    : undefined;

  const unqualified = (key: string): string =>
    `not coalesce(${qualifications?.fn("qualified_holders") ?? ""}(v_shift.${s("tenant")}, ${key}, 'member', (v_shift.${s("startsAt")} at time zone ${zone})::date) ? shift_assignment_check.user_id::text, false)`;

  const qualificationLoop =
    qualifications === undefined
      ? ""
      : `
  foreach v_key in array v_shift.${s("requiredQualifications")} loop
    if ${unqualified("v_key")} then
      ${
        warnOnly
          ? `v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'SHIFT_ASSIGNMENT_UNQUALIFIED', 'qualification', v_key));`
          : fail(
              "SHIFT_ASSIGNMENT_UNQUALIFIED",
              "the member doesn't hold a qualification the shift requires",
              "23514",
            )
      }
    end if;
  end loop;`;

  const restCheck =
    rest === 0
      ? ""
      : `
  if exists (
    select 1 from ${assignments} x
    where x.${a("tenant")} = v_shift.${s("tenant")} and x.${a("user")} = shift_assignment_check.user_id and x.${a("status")} = 'assigned'
      and x.${a("id")} is distinct from shift_assignment_check.assignment_id
      and tstzrange(x.${a("startsAt")}, x.${a("endsAt")}) && tstzrange(v_shift.${s("startsAt")} - interval '${String(rest)} hours', v_shift.${s("endsAt")} + interval '${String(rest)} hours')
  ) then
    ${fail("SHIFT_ASSIGNMENT_REST_TOO_SHORT", `the member would have less than ${String(rest)} hours between shifts`, "23514")}
  end if;`;

  const notifyUser = (
    type: string,
    user: string,
    summary: string,
    shift = "v_shift",
  ): string =>
    notifyShift(ctx, {
      type,
      tenant: `${shift}.${s("tenant")}`,
      shift: `${shift}.${s("id")}`,
      recipients: `jsonb_build_array(${user})`,
      summary: `'${summary}'`,
      key: `${sqlString(`${type}:`)} || ${shift}.${s("id")}::text || ':' || ${user}::text`,
      data: `jsonb_build_object('startsAt', ${shift}.${s("startsAt")}, 'endsAt', ${shift}.${s("endsAt")})`,
    });

  const claims = ctx.installed("notifications") ? "\n  v_claims text;" : "";

  const assignedCount = `(select count(*) from ${assignments} x where x.${a("shift")} = v_shift.${s("id")} and x.${a("status")} = 'assigned')`;

  const full = `if ${assignedCount} >= v_shift.${s("headcount")} then
    ${fail("SHIFT_FULL", "the shift has no open places", "23514")}
  end if;`;

  const upsert = (user: string, status: string): string =>
    `insert into ${assignments} (${a("tenant")}, ${a("shift")}, ${a("user")}, ${a("status")}, ${a("startsAt")}, ${a("endsAt")}${insertCol("assignments", "assignedBy")})
  values (v_shift.${s("tenant")}, v_shift.${s("id")}, ${user}, '${status}', v_shift.${s("startsAt")}, v_shift.${s("endsAt")}${insertVal("assignments", "assignedBy", "(select auth.uid())")})
  on conflict (${a("shift")}, ${a("user")}) do update set ${a("status")} = '${status}', ${a("startsAt")} = excluded.${a("startsAt")}, ${a("endsAt")} = excluded.${a("endsAt")}${has("assignments", "assignedBy") ? `, ${a("assignedBy")} = excluded.${a("assignedBy")}` : ""}${touch("assignments")}
  returning * into v_row;`;

  const overlap = fail(
    "SHIFT_ASSIGNMENT_OVERLAP",
    "the member has another shift at that time",
    "23P01",
  );

  const swapRecord = (event: string, extra: string): string =>
    ctx.record({
      type: event,
      payload: `jsonb_build_object('organizationId', v_swap.${w("tenant")}, 'swapId', v_swap.${w("id")}, 'assignmentId', v_swap.${w("assignment")}, 'shiftId', v_shift.${s("id")}, 'fromUserId', v_swap.${w("fromUser")}, 'toUserId', v_swap.${w("toUser")}${extra})`,
      subject: `'shifts/' || v_shift.${s("id")}::text`,
      tenant: `v_swap.${w("tenant")}`,
      audit: {
        category: "data",
        targetType: "shift_swap",
        recordId: `v_swap.${w("id")}::text`,
        summary:
          event === "shift_swap.requested"
            ? "'Shift swap requested'"
            : "'Shift swap decided'",
      },
    });

  const approvals =
    ctx.installed("approvals") && has("swaps", "approval")
      ? ctx.of("approvals")
      : undefined;

  const approvalCheck =
    approvals === undefined
      ? `if decide_shift_swap.approval_id is not null then
    ${swapInvalid("approval_id needs the approvals block")}
  end if;`
      : `if decide_shift_swap.approval_id is not null and not exists (
    select 1 from ${approvals.table("requests")} o where o.${approvals.col("requests", "id")} = decide_shift_swap.approval_id and o.${approvals.col("requests", "tenant")} = v_swap.${w("tenant")}
  ) then
    ${swapInvalid("the approval isn't in this organization")}
  end if;`;

  const decidedSets = [
    `${w("status")} = v_status`,
    `${w("decidedAt")} = now()`,
    has("swaps", "decidedBy") ? `${w("decidedBy")} = (select auth.uid())` : "",
    approvals === undefined
      ? ""
      : `${w("approval")} = coalesce(decide_shift_swap.approval_id, x.${w("approval")})`,
  ]
    .filter((set) => set !== "")
    .join(", ");

  return `
-- Checks that a member may work a shift: no other assigned shift overlaps,
-- no approved leave falls on its day, they hold its required qualifications
-- and they keep the minimum rest between shifts. Returns warnings (with
-- qualificationCheck "warn") and raises otherwise.
create or replace function ${check}(shift_id uuid, user_id uuid, assignment_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift ${shifts}%rowtype;
  v_warnings jsonb := '[]'::jsonb;
  v_key text;
begin
  select * into v_shift from ${shifts} x where x.${s("id")} = shift_assignment_check.shift_id;
  if not found then
    ${shiftNotFound}
  end if;
  if shift_assignment_check.user_id is null or not ${isMember(`v_shift.${s("tenant")}`, "shift_assignment_check.user_id")} then
    ${assignmentInvalid("the user isn't a member of this organization")}
  end if;
  if exists (
    select 1 from ${assignments} x
    where x.${a("tenant")} = v_shift.${s("tenant")} and x.${a("user")} = shift_assignment_check.user_id and x.${a("status")} = 'assigned'
      and x.${a("id")} is distinct from shift_assignment_check.assignment_id
      and tstzrange(x.${a("startsAt")}, x.${a("endsAt")}) && tstzrange(v_shift.${s("startsAt")}, v_shift.${s("endsAt")})
  ) then
    ${overlap}
  end if;${leaveCheck}${qualificationLoop}${restCheck}
  return v_warnings;
end;
$$;
revoke execute on function ${check}(uuid, uuid, uuid) from public, anon, authenticated;

-- Assigns a member to a shift. Returns the assignment with its warnings.
-- Assigning someone already on the shift changes nothing.
create or replace function ${fn("assign_shift")}(shift_id uuid, user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift ${shifts}%rowtype;
  v_row ${assignments}%rowtype;
  v_warnings jsonb := '[]'::jsonb;${claims}
begin
  select * into v_shift from ${shifts} x where x.${s("id")} = assign_shift.shift_id for update;
  if not found then
    ${shiftNotFound}
  end if;
  if not ${allowed(`v_shift.${s("tenant")}`, write)} then
    ${forbidden("not allowed to assign shifts")}
  end if;
  if v_shift.${s("status")} = 'canceled' then
    ${fail("SHIFT_CANCELED", "the shift is canceled", "55000")}
  end if;
  select * into v_row from ${assignments} x where x.${a("shift")} = v_shift.${s("id")} and x.${a("user")} = assign_shift.user_id;
  if found and v_row.${a("status")} = 'assigned' then
    return ${assignmentJson(ctx, "v_row")} || jsonb_build_object('warnings', v_warnings);
  end if;
  ${full}
  v_warnings := ${check}(v_shift.${s("id")}, assign_shift.user_id, v_row.${a("id")});
  ${ctx.hook("before_shift_assignment_create", [
    ["uuid", `v_shift.${s("id")}`],
    ["uuid", "assign_shift.user_id"],
  ])}
  begin
    ${upsert("assign_shift.user_id", "assigned")}
  exception when exclusion_violation then
    ${overlap}
  end;
  ${assignmentRecord(ctx, "shift_assignment.created", "v_row", "", "Shift assignment created")}
  if v_shift.${s("status")} = 'published' then
    ${notifyUser("shift_assignment.created", `v_row.${a("user")}`, "You are on a shift")}
  end if;
  ${ctx.hook("after_shift_assignment_create", [["uuid", `v_row.${a("id")}`]])}
  return ${assignmentJson(ctx, "v_row")} || jsonb_build_object('warnings', v_warnings);
end;
$$;
${userGrant(`${fn("assign_shift")}(uuid, uuid)`)}

-- Takes a member off a shift, or turns down their request for it.
create or replace function ${fn("unassign_shift")}(assignment_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift ${shifts}%rowtype;
  v_row ${assignments}%rowtype;
  v_was text;${claims}
begin
  select * into v_row from ${assignments} x where x.${a("id")} = unassign_shift.assignment_id for update;
  if not found then
    ${assignmentNotFound}
  end if;
  if not ${allowed(`v_row.${a("tenant")}`, write)} then
    ${forbidden("not allowed to assign shifts")}
  end if;
  select * into v_shift from ${shifts} x where x.${s("id")} = v_row.${a("shift")};
  v_was := v_row.${a("status")};
  if v_was <> 'released' then
    update ${assignments} x set ${a("status")} = 'released'${touch("assignments")}
    where x.${a("id")} = v_row.${a("id")}
    returning x.* into v_row;
    ${assignmentRecord(ctx, "shift_assignment.released", "v_row", ", 'reason', nullif(trim(unassign_shift.reason), '')", "Shift assignment released")}
    if v_was = 'assigned' and v_shift.${s("status")} = 'published' then
      ${notifyUser("shift_assignment.released", `v_row.${a("user")}`, "You are off a shift")}
    end if;
  end if;
  return ${assignmentJson(ctx, "v_row")};
end;
$$;
${userGrant(`${fn("unassign_shift")}(uuid, text)`)}

-- Asks for a place on a published open shift that hasn't started. A planner
-- decides with decide_shift_request.
create or replace function ${fn("request_open_shift")}(shift_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift ${shifts}%rowtype;
  v_row ${assignments}%rowtype;
  v_user uuid := (select auth.uid());
begin
  select * into v_shift from ${shifts} x where x.${s("id")} = request_open_shift.shift_id;
  if not found or v_shift.${s("status")} = 'draft' then
    ${shiftNotFound}
  end if;
  if v_user is null or not ${ctx.can("tenant", `v_shift.${s("tenant")}`, request)} then
    ${forbidden("not allowed to request shifts")}
  end if;
  if v_shift.${s("status")} = 'canceled' then
    ${fail("SHIFT_CANCELED", "the shift is canceled", "55000")}
  end if;
  if v_shift.${s("startsAt")} <= now() then
    ${assignmentInvalid("the shift has started")}
  end if;
  select * into v_row from ${assignments} x where x.${a("shift")} = v_shift.${s("id")} and x.${a("user")} = v_user;
  if found and v_row.${a("status")} <> 'released' then
    return ${assignmentJson(ctx, "v_row")};
  end if;
  ${full}
  perform ${check}(v_shift.${s("id")}, v_user, v_row.${a("id")});
  ${upsert("v_user", "requested")}
  return ${assignmentJson(ctx, "v_row")};
end;
$$;
${userGrant(`${fn("request_open_shift")}(uuid)`)}

-- Approves a request for an open shift (the member is assigned after the
-- same checks as assign_shift) or turns it down.
create or replace function ${fn("decide_shift_request")}(assignment_id uuid, approve boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift ${shifts}%rowtype;
  v_row ${assignments}%rowtype;
  v_warnings jsonb := '[]'::jsonb;${claims}
begin
  select * into v_row from ${assignments} x where x.${a("id")} = decide_shift_request.assignment_id;
  if not found then
    ${assignmentNotFound}
  end if;
  if not ${allowed(`v_row.${a("tenant")}`, manage)} then
    ${forbidden("not allowed to decide shift requests")}
  end if;
  if v_row.${a("status")} <> 'requested' then
    ${assignmentInvalid("the assignment isn't a pending request")}
  end if;
  select * into v_shift from ${shifts} x where x.${s("id")} = v_row.${a("shift")} for update;
  if coalesce(decide_shift_request.approve, false) then
    if v_shift.${s("status")} = 'canceled' then
      ${fail("SHIFT_CANCELED", "the shift is canceled", "55000")}
    end if;
    ${full}
    v_warnings := ${check}(v_shift.${s("id")}, v_row.${a("user")}, v_row.${a("id")});
    ${ctx.hook("before_shift_assignment_create", [
      ["uuid", `v_shift.${s("id")}`],
      ["uuid", `v_row.${a("user")}`],
    ])}
    begin
      update ${assignments} x set ${a("status")} = 'assigned', ${a("startsAt")} = v_shift.${s("startsAt")}, ${a("endsAt")} = v_shift.${s("endsAt")}${has("assignments", "assignedBy") ? `, ${a("assignedBy")} = (select auth.uid())` : ""}${touch("assignments")}
      where x.${a("id")} = v_row.${a("id")}
      returning x.* into v_row;
    exception when exclusion_violation then
      ${overlap}
    end;
    ${assignmentRecord(ctx, "shift_assignment.created", "v_row", "", "Shift assignment created")}
    ${notifyUser("shift_assignment.created", `v_row.${a("user")}`, "Your shift request is approved")}
    ${ctx.hook("after_shift_assignment_create", [["uuid", `v_row.${a("id")}`]])}
  else
    update ${assignments} x set ${a("status")} = 'released'${touch("assignments")}
    where x.${a("id")} = v_row.${a("id")}
    returning x.* into v_row;
    ${assignmentRecord(ctx, "shift_assignment.released", "v_row", ", 'reason', 'request_rejected'", "Shift request rejected")}
    ${notifyUser("shift_assignment.released", `v_row.${a("user")}`, "Your shift request is turned down")}
  end if;
  return ${assignmentJson(ctx, "v_row")} || jsonb_build_object('warnings', v_warnings);
end;
$$;
${userGrant(`${fn("decide_shift_request")}(uuid, boolean)`)}

-- Offers an assigned shift that hasn't started to another member. A manager
-- decides with decide_shift_swap; the member who asked may withdraw it there.
create or replace function ${fn("request_shift_swap")}(assignment_id uuid, to_user_id uuid, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift ${shifts}%rowtype;
  v_row ${assignments}%rowtype;
  v_swap ${swaps}%rowtype;${claims}
begin
  select * into v_row from ${assignments} x where x.${a("id")} = request_shift_swap.assignment_id;
  if not found then
    ${assignmentNotFound}
  end if;
  if not (v_row.${a("user")} = (select auth.uid()) or ${allowed(`v_row.${a("tenant")}`, write)}) then
    ${forbidden("not allowed to swap this shift")}
  end if;
  select * into v_shift from ${shifts} x where x.${s("id")} = v_row.${a("shift")};
  if v_row.${a("status")} <> 'assigned' or v_shift.${s("status")} = 'canceled' or v_shift.${s("startsAt")} <= now() then
    ${swapInvalid("only an assigned shift that hasn't started can be swapped")}
  end if;
  if request_shift_swap.to_user_id is null or request_shift_swap.to_user_id = v_row.${a("user")} or not ${isMember(`v_row.${a("tenant")}`, "request_shift_swap.to_user_id")} then
    ${swapInvalid("the swap goes to another member of this organization")}
  end if;
  if request_shift_swap.note is not null and length(request_shift_swap.note) > 2000 then
    ${swapInvalid("a note is at most 2000 characters")}
  end if;
  if exists (select 1 from ${swaps} x where x.${w("assignment")} = v_row.${a("id")} and x.${w("status")} = 'pending') then
    ${swapInvalid("the shift already has a pending swap")}
  end if;
  insert into ${swaps} (${w("tenant")}, ${w("assignment")}, ${w("fromUser")}, ${w("toUser")}${insertCol("swaps", "note")})
  values (v_row.${a("tenant")}, v_row.${a("id")}, v_row.${a("user")}, request_shift_swap.to_user_id${insertVal("swaps", "note", "nullif(trim(request_shift_swap.note), '')")})
  returning * into v_swap;
  ${swapRecord("shift_swap.requested", "")}
  ${notifyUser("shift_swap.requested", `v_swap.${w("toUser")}`, "A shift swap is offered to you")}
  return ${swapJson(ctx, "v_swap")};
end;
$$;
${userGrant(`${fn("request_shift_swap")}(uuid, uuid, text)`)}

-- Approves a pending swap (the other member takes the shift after the same
-- checks as assign_shift) or rejects it. The member who asked may withdraw it
-- (approve false). approval_id links an approvals request.
create or replace function ${fn("decide_shift_swap")}(swap_id uuid, approve boolean, approval_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift ${shifts}%rowtype;
  v_row ${assignments}%rowtype;
  v_swap ${swaps}%rowtype;
  v_status text;${claims}
begin
  select * into v_swap from ${swaps} x where x.${w("id")} = decide_shift_swap.swap_id for update;
  if not found then
    ${fail("SHIFT_SWAP_NOT_FOUND", "shift swap not found", "P0002")}
  end if;
  if ${allowed(`v_swap.${w("tenant")}`, manage)} then
    v_status := case when coalesce(decide_shift_swap.approve, false) then 'approved' else 'rejected' end;
  elsif v_swap.${w("fromUser")} = (select auth.uid()) and not coalesce(decide_shift_swap.approve, false) then
    v_status := 'canceled';
  else
    ${forbidden("not allowed to decide shift swaps")}
  end if;
  if v_swap.${w("status")} <> 'pending' then
    ${swapInvalid("the swap is already decided")}
  end if;
  ${approvalCheck}
  select * into v_row from ${assignments} x where x.${a("id")} = v_swap.${w("assignment")};
  select * into v_shift from ${shifts} x where x.${s("id")} = v_row.${a("shift")} for update;
  if v_status = 'approved' then
    if v_row.${a("status")} <> 'assigned' or v_shift.${s("status")} = 'canceled' then
      ${swapInvalid("the shift is no longer assigned to the member who asked")}
    end if;
    perform ${check}(v_shift.${s("id")}, v_swap.${w("toUser")}, null);
    update ${assignments} x set ${a("status")} = 'released'${touch("assignments")}
    where x.${a("id")} = v_row.${a("id")}
    returning x.* into v_row;
    ${assignmentRecord(ctx, "shift_assignment.released", "v_row", ", 'reason', 'swapped'", "Shift assignment released")}
    begin
      ${upsert(`v_swap.${w("toUser")}`, "assigned")}
    exception when exclusion_violation then
      ${overlap}
    end;
    ${assignmentRecord(ctx, "shift_assignment.created", "v_row", "", "Shift assignment created")}
  end if;
  update ${swaps} x set ${decidedSets}
  where x.${w("id")} = v_swap.${w("id")}
  returning x.* into v_swap;
  ${swapRecord("shift_swap.decided", `, 'status', v_swap.${w("status")}`)}
  if v_status <> 'canceled' then
    ${notifyUser("shift_swap.decided", `v_swap.${w("fromUser")}`, "Your shift swap is decided")}
  end if;
  if v_status = 'approved' then
    ${notifyUser("shift_assignment.created", `v_swap.${w("toUser")}`, "You took over a shift")}
  end if;
  return ${swapJson(ctx, "v_swap")};
end;
$$;
${userGrant(`${fn("decide_shift_swap")}(uuid, boolean, uuid)`)}
`;
}
