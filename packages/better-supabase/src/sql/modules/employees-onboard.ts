import type { BlockSqlContext } from "../context.ts";
import type { EmployeeNames } from "./employees-functions.ts";

import { userGrant } from "../shared.ts";

/**
 * `onboard_with_program`: `people.onboard` as one atomic function (ADR 1235).
 * It creates the employee, enrolls them in the onboarding program and sets the
 * enrollment dates through the same functions the single steps use, so each
 * keeps its own permission check, hooks and events. A failed enrollment now
 * rolls the employee back. It needs the enrollments module; without it the
 * function is not written.
 */
export function onboardWithProgram(
  ctx: BlockSqlContext,
  n: EmployeeNames,
): string {
  if (!ctx.installed("enrollments")) {
    return "";
  }

  const enrollments = ctx.of("enrollments");

  return `
-- Creates the employee (attrs as create_employee), enrolls them in the program
-- and sets the enrollment dates ({ startsAt?, endsAt? }, optional), in one
-- transaction. Returns { employee, enrollment }.
create or replace function ${n.fn("onboard_with_program")}(tenant ${ctx.idType}, attrs jsonb, program text, dates jsonb default null)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_employee jsonb;
  v_enrollment jsonb;
begin
  v_employee := ${n.fn("create_employee")}(onboard_with_program.tenant, onboard_with_program.attrs);
  v_enrollment := ${enrollments.fn("enroll")}(onboard_with_program.tenant, onboard_with_program.program, 'employee', v_employee ->> 'id');
  if onboard_with_program.dates is not null and jsonb_typeof(onboard_with_program.dates) = 'object' and onboard_with_program.dates <> '{}'::jsonb then
    v_enrollment := ${enrollments.fn("set_enrollment_dates")}((v_enrollment ->> 'id')::uuid, onboard_with_program.dates);
  end if;
  return jsonb_build_object('employee', v_employee, 'enrollment', v_enrollment);
end;
$$;
${userGrant(`${n.fn("onboard_with_program")}(${ctx.idType}, jsonb, text, jsonb)`)}
`;
}
