import type { BlockSqlContext } from "../context.ts";
import type { EmployeeNames } from "./employees-functions.ts";

import { userGrant } from "../shared.ts";

/**
 * `offboard_with_work`: `people.offboard` as one atomic function (ADR 1235). It
 * offboards the employee, cancels their active enrollments and releases their
 * open shift assignments (assigned or requested) that start in the next
 * `window_days` days, all in one transaction through the same functions the
 * single steps use, so each keeps its own permission check, hooks and events.
 * Enrollments a module drives (a program key with a colon) stay, as
 * `cancel_enrollment` refuses them. It needs the enrollments and shifts
 * modules; without them it is not written.
 */
export function offboardWithWork(
  ctx: BlockSqlContext,
  n: EmployeeNames,
): string {
  if (!ctx.installed("enrollments") || !ctx.installed("shifts")) {
    return "";
  }

  const enrollments = ctx.of("enrollments");
  const shifts = ctx.of("shifts");
  const e = (column: string): string => n.c("employees", column);
  const en = (column: string): string => enrollments.col("enrollments", column);
  const a = (column: string): string => shifts.col("assignments", column);

  return `
-- Offboards the employee, cancels their active enrollments and releases their
-- open shift assignments that start from today to window_days days ahead, in
-- one transaction. Steps that are already done change nothing, so it can run
-- again. Returns the employee, and how many enrollments and assignments it
-- ended.
create or replace function ${n.fn("offboard_with_work")}(employee uuid, end_date date, reason text, window_days integer default 30)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_employee jsonb;
  v_user uuid;
  v_id uuid;
  v_enrollments integer := 0;
  v_assignments integer := 0;
begin
  v_employee := ${n.fn("offboard_employee")}(offboard_with_work.employee, offboard_with_work.end_date, offboard_with_work.reason);
  select x.${e("user")} into v_user from ${n.t("employees")} x where x.${e("id")} = offboard_with_work.employee;
  for v_id in
    select x.${en("id")} from ${enrollments.table("enrollments")} x
    where x.${en("subjectType")} = 'employee' and x.${en("subjectId")} = offboard_with_work.employee::text and x.${en("status")} = 'active'
      and position(':' in x.${en("program")}) = 0
    order by x.${en("id")}
  loop
    perform ${enrollments.fn("cancel_enrollment")}(v_id);
    v_enrollments := v_enrollments + 1;
  end loop;
  if v_user is not null then
    for v_id in
      select x.${a("id")} from ${shifts.table("assignments")} x
      where x.${a("user")} = v_user and x.${a("status")} in ('assigned', 'requested')
        and x.${a("startsAt")} >= current_date and x.${a("startsAt")} < current_date + offboard_with_work.window_days
      order by x.${a("startsAt")}, x.${a("id")}
    loop
      perform ${shifts.fn("unassign_shift")}(v_id, offboard_with_work.reason);
      v_assignments := v_assignments + 1;
    end loop;
  end if;
  return jsonb_build_object('employee', v_employee, 'enrollments', v_enrollments, 'assignments', v_assignments);
end;
$$;
${userGrant(`${n.fn("offboard_with_work")}(uuid, date, text, integer)`)}
`;
}
