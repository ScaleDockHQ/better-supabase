import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";

/** The engagement type a booking's meeting gets. */
const MEETING = "meeting";

/** Whether `blocks.engagements.options.bookings` turns the integration on. */
export function logsBookings(
  ctx: BlockSqlContext,
  types: readonly string[],
): boolean {
  if (!ctx.flag("bookings", false)) {
    return false;
  }

  if (!ctx.installed("bookings")) {
    throw new TypeError(
      "blocks.engagements.options.bookings needs the bookings block",
    );
  }

  if (!types.includes(MEETING)) {
    throw new TypeError(
      'blocks.engagements.options.bookings needs "meeting" in blocks.engagements.options.types',
    );
  }

  return true;
}

/**
 * The SQL that keeps a meeting engagement per confirmed booking: logged on
 * confirmation, moved on a reschedule and closed as cancelled on a
 * cancellation, on the person with the booker's email and their company.
 */
export function bookingEngagementsSql(ctx: BlockSqlContext): string {
  const bookings = ctx.of("bookings");
  const t = (table: string): string => ctx.table(table);
  const e = (column: string): string => ctx.col("engagements", column);
  const l = (column: string): string => ctx.col("links", column);
  const b = (column: string): string => bookings.col("bookings", column);
  const s = (column: string): string => bookings.col("services", column);
  const fn = ctx.fn("bsb_booking_engagement");
  const trigger = ctx.naming.rename("bookings_engagement");

  const createdBy = bookings.has("bookings", "createdBy")
    ? `new.${b("createdBy")}`
    : "null::uuid";

  const notes = bookings.has("bookings", "notes")
    ? `new.${b("notes")}`
    : "null::text";

  const parties = ctx.installed("parties") ? ctx.of("parties") : undefined;

  const linkParties =
    parties === undefined
      ? { declare: "", link: "" }
      : partyLinksSql(ctx, parties, {
          email: `new.${b("customerEmail")}`,
          user: `new.${b("customerUser")}`,
        });

  const payload = `jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', '${MEETING}', 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects)`;

  const record = (event: string): string =>
    ctx.record({
      type: event,
      payload,
      subject: `'engagements/' || v_id::text`,
      tenant: "v_tenant::text",
      audit: false,
    });

  const subjects = `
    v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx.${l("subjectType")}, 'id', sx.${l("subjectId")}) order by sx.${l("position")}) from ${t("links")} sx where sx.${l("engagement")} = v_id), '[]'::jsonb);
    v_first := v_subjects -> 0;`;

  return `
-- A meeting engagement for each confirmed booking (options.bookings), with
-- the external ref booking:<id>: moved when the booking moves, and closed
-- with the outcome cancelled when it is cancelled.
create or replace function ${fn}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ref text := 'booking:' || new.${b("id")}::text;
  v_tenant ${ctx.idType} := new.${b("tenant")};
  v_id uuid;
  v_inserted boolean;
  v_title text;
  v_owner uuid := ${createdBy};
  v_person uuid;
  v_person_owner uuid;
  v_subjects jsonb;
  v_first jsonb;
begin
  if new.${b("status")} = 'confirmed' then
    if tg_op = 'UPDATE' and old.${b("status")} = 'confirmed' and old.${b("during")} = new.${b("during")} then
      return null;
    end if;${linkParties.declare}
    select left(coalesce(sv.${s("name")}, 'Booking') || coalesce(' with ' || nullif(trim(new.${b("customerName")}), ''), ''), 500)
    into v_title
    from ${bookings.table("services")} sv where sv.${s("id")} = new.${b("service")};
    insert into ${t("engagements")} (${e("tenant")}, ${e("type")}, ${e("title")}, ${e("body")}, ${e("owner")}, ${e("dueAt")}, ${e("durationSeconds")}, ${e("externalRef")}, ${e("createdBy")})
    values (v_tenant, '${MEETING}', coalesce(v_title, 'Booking'), ${notes}, v_owner, lower(new.${b("during")}),
      extract(epoch from upper(new.${b("during")}) - lower(new.${b("during")}))::integer, v_ref, ${createdBy})
    on conflict (${e("tenant")}, ${e("externalRef")}) where ${e("externalRef")} is not null do update set
      ${e("dueAt")} = excluded.${e("dueAt")}, ${e("durationSeconds")} = excluded.${e("durationSeconds")},
      ${e("doneAt")} = null, ${e("outcome")} = null, ${e("updatedAt")} = now()
    returning ${e("id")}, (xmax = 0) into v_id, v_inserted;${linkParties.link}${subjects}
    if v_inserted then
      ${record("engagement.logged")}
    else
      ${record("engagement.updated")}
    end if;
  elsif new.${b("status")} = 'cancelled' and tg_op = 'UPDATE' and old.${b("status")} = 'confirmed' then
    update ${t("engagements")} x set
      ${e("doneAt")} = coalesce(new.${b("cancelledAt")}, now()),
      ${e("outcome")} = left('cancelled' || coalesce(': ' || nullif(trim(new.${b("cancelReason")}), ''), ''), 500),
      ${e("updatedAt")} = now()
    where x.${e("tenant")} = v_tenant and x.${e("externalRef")} = v_ref and x.${e("doneAt")} is null
    returning x.${e("id")} into v_id;
    if v_id is not null then${subjects}
      ${record("engagement.completed")}
    end if;
  end if;
  return null;
end;
$$;
revoke all on function ${fn}() from public, anon, authenticated;
drop trigger if exists ${trigger} on ${bookings.table("bookings")};
create trigger ${trigger}
after insert or update of ${b("status")}, ${b("during")} on ${bookings.table("bookings")}
for each row execute function ${fn}();
`;
}

/**
 * Links the engagement to the active person the booking names (by user, then by
 * email) and that person's first company, and gives the meeting the person's
 * owner when no member made the booking.
 */
function partyLinksSql(
  ctx: BlockSqlContext,
  parties: BlockSqlContext,
  booking: { readonly email: string; readonly user: string },
): { readonly declare: string; readonly link: string } {
  const pe = (column: string): string => parties.col("people", column);
  const co = (column: string): string => parties.col("companies", column);
  const li = (column: string): string => parties.col("links", column);
  const l = (column: string): string => ctx.col("links", column);
  const person = sqlString(parties.naming.rename("person"));
  const company = sqlString(parties.naming.rename("company"));

  return {
    declare: `
    select p.${pe("id")}, p.${pe("owner")} into v_person, v_person_owner
    from ${parties.table("people")} p
    where p.${pe("tenant")} = v_tenant and p.${pe("archivedAt")} is null and p.${pe("mergedInto")} is null
      and ((${booking.user} is not null and p.${pe("user")} = ${booking.user})
        or (${booking.email} is not null and lower(p.${pe("email")}) = lower(${booking.email})))
    order by (${booking.user} is not null and p.${pe("user")} = ${booking.user}) desc, p.${pe("createdAt")}
    limit 1;
    v_owner := coalesce(v_owner, v_person_owner);`,
    link: `
    if v_person is not null then
      insert into ${ctx.table("links")} (${l("tenant")}, ${l("engagement")}, ${l("subjectType")}, ${l("subjectId")}, ${l("position")})
      values (v_tenant, v_id, ${person}, v_person::text, 1)
      on conflict do nothing;
      insert into ${ctx.table("links")} (${l("tenant")}, ${l("engagement")}, ${l("subjectType")}, ${l("subjectId")}, ${l("position")})
      select v_tenant, v_id, ${company}, c.${co("id")}::text, 2
      from ${parties.table("links")} k
      join ${parties.table("companies")} c on c.${co("id")} = k.${li("company")}
      where k.${li("person")} = v_person and c.${co("archivedAt")} is null
      order by k.${li("isPrimary")} desc, k.${li("createdAt")}
      limit 1
      on conflict do nothing;
    end if;`,
  };
}
