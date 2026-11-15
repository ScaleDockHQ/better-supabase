import type { BookingsEvents } from "../../blocks/bookings/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
} from "../context.ts";
import type { Parts } from "./bookings-public.ts";

import { fail, userGrant } from "../shared.ts";
import { allowed, bookingJson, record } from "./bookings-public.ts";

/**
 * `archive_booking` and `restore_booking`, when the bookings table has the
 * `archivedAt` column.
 */
export function archiveFunctions(p: Parts): string {
  const { ctx, b } = p;
  const fn = (name: string): string => ctx.fn(name);

  return ctx.has("bookings", "archivedAt")
    ? ["archive", "restore"]
        .map((verb) => {
          const past = verb === "archive" ? "archived" : "restored";

          return `
-- ${verb === "archive" ? "Archives a cancelled booking, or one that has ended: it leaves the lists and keeps its history." : "Restores an archived booking to the lists."}
create or replace function ${fn(`${verb}_booking`)}(booking uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_booking ${p.bookings}%rowtype;
begin
  select * into v_booking from ${p.bookings} bk where bk.${b("id")} = ${verb}_booking.booking for update;
  if not found or not ${allowed(p.scope, `v_booking.${b("tenant")}`, p.manage)} then
    ${fail("BOOKING_NOT_FOUND", "booking not found", "P0002")}
  end if;
  if v_booking.${b("archivedAt")} ${verb === "archive" ? "is not null" : "is null"} then
    return ${bookingJson(p, "v_booking")};
  end if;${
    verb === "archive"
      ? `
  if v_booking.${b("status")} <> 'cancelled' and upper(v_booking.${b("during")}) > now() then
    ${fail("BOOKING_ACTIVE", "only a cancelled booking or one that has ended is archived", "55000")}
  end if;`
      : ""
  }
  update ${p.bookings} bk set ${b("archivedAt")} = ${verb === "archive" ? "now()" : "null"}, ${b("updatedAt")} = now()
  where bk.${b("id")} = v_booking.${b("id")} returning * into v_booking;
  ${record(p, `booking.${past}`, `v_booking.${b("id")}`, `v_booking.${b("tenant")}`)}
  return ${bookingJson(p, "v_booking")};
end;
$$;
${userGrant(`${fn(`${verb}_booking`)}(uuid)`)}
`;
        })
        .join("")
    : "";
}

/** The contract entries of the archive functions. */
export const archiveContract = (
  ctx: BlockSqlContext,
): readonly BlockSqlContractFunction[] =>
  ctx.has("bookings", "archivedAt")
    ? [
        { name: "archive_booking", args: ["uuid"], returns: "jsonb" },
        { name: "restore_booking", args: ["uuid"], returns: "jsonb" },
      ]
    : [];

/** The `booking.archived` and `booking.restored` events. */
export const ARCHIVE_EVENTS: Pick<
  BlockSqlEvents<BookingsEvents>,
  "booking.archived" | "booking.restored"
> = {
  "booking.archived": {
    subject: "bookings",
    payload: ["organizationId", "id", "resourceId", "serviceId"],
  },
  "booking.restored": {
    subject: "bookings",
    payload: ["organizationId", "id", "resourceId", "serviceId"],
  },
};
