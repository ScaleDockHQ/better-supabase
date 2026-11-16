import type { Parts } from "./bookings-public.ts";

import {
  filterAny,
  filterFirst,
  filterFlag,
  listBody,
  listDeclare,
  searchPattern,
} from "../list-template.ts";
import { fail, userGrant } from "../shared.ts";
import { bookingJson } from "./bookings-public.ts";

/**
 * `page_bookings` and `get_booking` (ADR 1077). Both run as the caller, so the
 * table's policy shows a tenant's bookings to readers and a customer their own,
 * as `list_bookings` does.
 */
export function bookingPages(p: Parts): string {
  const { ctx, b } = p;
  const fn = (name: string): string => ctx.fn(name);
  const key = { expr: `bk.${b("id")}`, dir: "desc", type: "uuid" } as const;

  const starts = [
    { expr: `lower(bk.${b("during")})`, dir: "desc", type: "timestamptz" },
    key,
  ] as const;

  const spec = {
    name: "page_bookings",
    from: p.bookings,
    alias: "bk",
    where: [
      `bk.${b("tenant")} = page_bookings.tenant`,
      filterAny("status", `bk.${b("status")}::text`),
      filterAny("resourceId", `bk.${b("resource")}`, "uuid"),
      filterAny("serviceId", `bk.${b("service")}`, "uuid"),
      filterAny("customerId", `bk.${b("customerUser")}::text`),
      `(${filterFirst("from")} is null or upper(bk.${b("during")}) > (${filterFirst("from")})::timestamptz)`,
      `(${filterFirst("to")} is null or lower(bk.${b("during")}) < (${filterFirst("to")})::timestamptz)`,
      ctx.has("bookings", "archivedAt")
        ? `(${filterFlag("archived")} or bk.${b("archivedAt")} is null)`
        : "true",
      `(v_search is null or bk.${b("customerName")} ilike v_search or bk.${b("customerEmail")} ilike v_search)`,
    ],
    keys: starts,
    sorts: {
      startsAt: starts,
      createdAt: [
        { expr: `bk.${b("createdAt")}`, dir: "desc", type: "timestamptz" },
        key,
      ],
      customerName: [
        {
          expr: `lower(coalesce(bk.${b("customerName")}, ''))`,
          dir: "asc",
          type: "text",
        },
        key,
      ],
    },
    facets: {
      status: `bk.${b("status")}::text`,
      resourceId: `bk.${b("resource")}::text`,
    },
    rowJson: bookingJson(p, "bk"),
    defaultLimit: 50,
    maxLimit: 200,
    invalid: (message: string) => fail("BOOKING_INVALID", message, "22023"),
  } as const;

  return `
-- The tenant's bookings as a keyset page, the latest start first (ADR 1077).
-- filters is { status, resourceId, serviceId, customerId (each a value or a
-- list), from, to (the first value counts: bookings that overlap the window),
-- archived (true adds archived bookings), search (customer name, email), sort
-- (startsAt, createdAt, customerName), direction, facet, count, limit, after,
-- offset, paged, total, totalCap }.
create or replace function ${fn("page_bookings")}(tenant ${ctx.idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_bookings.filters, '{}'::jsonb);
  v_search text := ${searchPattern()};
  ${listDeclare(spec)}
begin
  ${listBody(spec)}
end;
$$;
${userGrant(`${fn("page_bookings")}(${ctx.idType}, jsonb)`)}

-- One booking the caller reads, or null.
create or replace function ${fn("get_booking")}(booking uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select ${bookingJson(p, "bk")} from ${p.bookings} bk where bk.${b("id")} = get_booking.booking
$$;
${userGrant(`${fn("get_booking")}(uuid)`)}
`;
}
