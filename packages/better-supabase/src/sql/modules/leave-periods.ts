import type { BlockSqlContext } from "../context.ts";

import { serviceGrant } from "../shared.ts";

/** Functions the contract treats as internal: helpers, and the period engine's. */
export const INTERNAL = [
  "leave_available",
  "leave_post",
  "leave_posted",
  "leave_range_close_blockers",
  "leave_close_range",
] as const;

/** Blocks leave writes to or reads from when they are installed. */
export const INTEGRATES = [
  "outbox",
  "audit",
  "employees",
  "share-links",
  "teams",
  "periods",
] as const;

/**
 * The period engine's view of a leave year (ADR 0197): pending requests that
 * start in the year block the close, and the close is `close_leave_year`.
 * `join` and `pending` are the approval join and the pending test for request
 * alias `r` and approval alias `ap`.
 */
export function periodFunctions(
  ctx: BlockSqlContext,
  join: string,
  pending: string,
): string {
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const requests = ctx.table("requests");
  const tenant = ctx.col("requests", "tenant");
  const startsOn = ctx.col("requests", "startsOn");

  return `
create or replace function ${fn("leave_range_close_blockers")}(tenant ${idType}, starts_on date, ends_on date)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select case when exists (
    select 1 from ${requests} r${join}
    where r.${tenant} = leave_range_close_blockers.tenant
      and r.${startsOn} between leave_range_close_blockers.starts_on and leave_range_close_blockers.ends_on
      and ${pending}
  ) then array['pending_requests']::text[] else '{}'::text[] end
$$;
${serviceGrant(`${fn("leave_range_close_blockers")}(${idType}, date, date)`)}

create or replace function ${fn("leave_close_range")}(tenant ${idType}, starts_on date, ends_on date)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform ${fn("close_leave_year")}(leave_close_range.tenant, extract(year from leave_close_range.starts_on)::integer);
end;
$$;
${serviceGrant(`${fn("leave_close_range")}(${idType}, date, date)`)}
`;
}
