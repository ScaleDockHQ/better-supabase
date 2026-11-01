import type { BlockSqlContext } from "../context.ts";

/** What `time_week_approved` reads from the time-tracking module. */
export interface ApprovedWeekNames {
  readonly timesheets: string;
  readonly t: (column: string) => string;
  readonly tOwner: string;
  readonly statusMode: boolean;
  readonly weekOf: (at: string, user: string) => string;
}

/**
 * `time_week_approved(tenant, user_id, at)`: whether the week an instant falls
 * in has an approved timesheet. Payroll runs read only the entries of such
 * weeks (ADR 0172).
 */
export function approvedWeekFunction(
  ctx: BlockSqlContext,
  names: ApprovedWeekNames,
): string {
  const { timesheets, t, tOwner, statusMode, weekOf } = names;
  const fn = ctx.fn("time_week_approved");

  const approved = statusMode
    ? ctx.is("timesheets", "status", `s.${t("status")}`, ["approved"])
    : `s.${t("approvedAt")} is not null`;

  return `-- Whether the week an instant falls in has an approved timesheet. Payroll runs
-- read only the entries of approved weeks.
create or replace function ${fn}(tenant ${ctx.idType}, user_id uuid, at timestamptz)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from ${timesheets} s
    where s.${t("tenant")} = time_week_approved.tenant and s.${tOwner} = time_week_approved.user_id
      and s.${t("week")} = ${weekOf("time_week_approved.at", "time_week_approved.user_id")}
      and ${approved}
  );
$$;
revoke execute on function ${fn}(${ctx.idType}, uuid, timestamptz) from public, anon, authenticated;
`;
}
