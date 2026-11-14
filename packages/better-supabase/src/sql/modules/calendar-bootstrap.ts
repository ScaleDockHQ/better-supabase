import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";

import { userGrant } from "../shared.ts";

/** The reminders block's subject type for an event, as `reminderRule` writes it. */
const EVENT_SUBJECT = "calendar_event";

/** Whether the caller's reminders on events can ride along with the bootstrap. */
function withReminders(ctx: BlockSqlContext): boolean {
  return (
    ctx.installed("reminders") && ctx.of("reminders").hasTable("reminders")
  );
}

/**
 * The `calendar_bootstrap(...)` function: what a calendar page reads in one
 * call, the calendars, the events that can fall in the month, the events of a
 * second range and the caller's reminders on events.
 */
export function calendarBootstrapFunction(ctx: BlockSqlContext): string {
  const name = ctx.fn("calendar_bootstrap");
  const reminders = withReminders(ctx);

  const remindersSql = reminders
    ? `
  -- list_my_reminders needs reminders.manage; a caller without it gets none.
  begin
    v_reminders := ${ctx.of("reminders").fn("list_my_reminders")}(calendar_bootstrap.tenant, '${EVENT_SUBJECT}', null);
  exception when insufficient_privilege then
    v_reminders := '[]'::jsonb;
  end;`
    : "";

  return `
-- The calendars of a tenant, the events that can fall in [range_start,
-- range_end), those of [upcoming_start, upcoming_end) when both are given, and
-- the caller's reminders on events: one call instead of one per read. Each part
-- is what list_calendars, list_calendar_events and list_my_reminders return, and
-- it runs as the caller, so the policies decide what it holds.
create or replace function ${name}(tenant ${ctx.idType}, range_start timestamptz, range_end timestamptz, upcoming_start timestamptz default null, upcoming_end timestamptz default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_calendars jsonb := ${ctx.fn("list_calendars")}(calendar_bootstrap.tenant);
  v_ids uuid[];
  v_events jsonb := '[]'::jsonb;
  v_upcoming jsonb := '[]'::jsonb;
  v_reminders jsonb := '[]'::jsonb;
begin
  select coalesce(array_agg((c ->> 'id')::uuid), '{}'::uuid[]) into v_ids
    from jsonb_array_elements(v_calendars) c;
  if cardinality(v_ids) > 0 then
    v_events := ${ctx.fn("list_calendar_events")}(v_ids, calendar_bootstrap.range_start, calendar_bootstrap.range_end);
    if calendar_bootstrap.upcoming_start is not null and calendar_bootstrap.upcoming_end is not null then
      v_upcoming := ${ctx.fn("list_calendar_events")}(v_ids, calendar_bootstrap.upcoming_start, calendar_bootstrap.upcoming_end);
    end if;${remindersSql}
  end if;
  return jsonb_build_object('calendarList', v_calendars, 'monthEvents', v_events, 'upcomingEvents', v_upcoming, 'myReminders', v_reminders);
end;
$$;
${userGrant(`${name}(${ctx.idType}, timestamptz, timestamptz, timestamptz, timestamptz)`)}
`;
}

export function calendarBootstrapContract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "calendar_bootstrap",
      args: [
        "{id}",
        "timestamptz",
        "timestamptz",
        "timestamptz",
        "timestamptz",
      ],
      returns: "jsonb",
    },
  ];
}
