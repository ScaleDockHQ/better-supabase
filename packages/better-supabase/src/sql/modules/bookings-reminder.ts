import type { BlockSqlContext } from "../context.ts";

import { userGrant } from "../shared.ts";

/**
 * `book_with_reminder`: `scheduling.bookWithReminder` as one atomic function
 * (ADR 1235). It books the slot with `hold_booking` (confirmed) and saves the
 * caller's reminder on the booking with `upsert_reminder`, so each keeps its
 * own permission check, hooks and events. A failed reminder now rolls the
 * booking back. It needs the reminders module; without it the function is not
 * written.
 */
export function bookWithReminder(ctx: BlockSqlContext): string {
  if (!ctx.installed("reminders")) {
    return "";
  }

  const reminders = ctx.of("reminders");
  const services = ctx.table("services");
  const tenant = ctx.col("services", "tenant");
  const id = ctx.col("services", "id");
  const fn = ctx.fn("book_with_reminder");

  return `
-- Books and confirms a slot, then sets the caller's reminder offset_minutes
-- before it, in one transaction. Returns { booking, reminder }.
create or replace function ${fn}(service uuid, resource uuid, starts_at timestamptz, customer jsonb, offset_minutes integer)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant ${ctx.idType};
  v_booking jsonb;
  v_reminder jsonb;
begin
  select s.${tenant} into v_tenant from ${services} s where s.${id} = book_with_reminder.service;
  v_booking := ${ctx.fn("hold_booking")}(book_with_reminder.service, book_with_reminder.resource, book_with_reminder.starts_at, book_with_reminder.customer, true);
  v_reminder := ${reminders.fn("upsert_reminder")}(
    tenant => v_tenant,
    subject_type => 'booking',
    subject_id => v_booking ->> 'id',
    offset_minutes => book_with_reminder.offset_minutes
  );
  return jsonb_build_object('booking', v_booking, 'reminder', v_reminder);
end;
$$;
${userGrant(`${fn}(uuid, uuid, timestamptz, jsonb, integer)`)}
`;
}
