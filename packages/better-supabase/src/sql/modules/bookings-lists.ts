import type { Parts } from "./bookings-public.ts";

import { userGrant } from "../shared.ts";

/** `list_booking_resources` and `list_booking_services`, read as the caller. */
export function catalogLists(p: Parts): string {
  const { ctx, r, s } = p;
  const fn = (name: string): string => ctx.fn(name);

  return `
-- The tenant's resources, as the caller (the table's policy decides who sees
-- them). Inactive ones are left out unless include_inactive is set.
create or replace function ${fn("list_booking_resources")}(tenant ${ctx.idType}, include_inactive boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', rs.${r("id")}, 'name', rs.${r("name")}, 'kind', rs.${r("kind")},
    'capacity', rs.${r("capacity")}, 'tz', rs.${r("tz")}, 'active', rs.${r("active")},
    'calendarId', ${ctx.has("resources", "calendar") ? `rs.${r("calendar")}` : "null"},
    'hostUserId', ${ctx.has("resources", "host") ? `rs.${r("host")}` : "null"}
  ) order by rs.${r("name")}, rs.${r("id")}), '[]'::jsonb)
  from ${p.resources} rs
  where rs.${r("tenant")} = list_booking_resources.tenant
    and (list_booking_resources.include_inactive or rs.${r("active")})
$$;
${userGrant(`${fn("list_booking_resources")}(${ctx.idType}, boolean)`)}

-- The tenant's services with their durations as interval text, as the
-- caller. Inactive ones are left out unless include_inactive is set.
create or replace function ${fn("list_booking_services")}(tenant ${ctx.idType}, include_inactive boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', sv.${s("id")}, 'name', sv.${s("name")},
    'duration', sv.${s("duration")}::text,
    'bufferBefore', sv.${s("bufferBefore")}::text,
    'bufferAfter', sv.${s("bufferAfter")}::text,
    'resourceKinds', to_jsonb(sv.${s("resourceKinds")}),
    'active', sv.${s("active")}
  ) order by sv.${s("name")}, sv.${s("id")}), '[]'::jsonb)
  from ${p.services} sv
  where sv.${s("tenant")} = list_booking_services.tenant
    and (list_booking_services.include_inactive or sv.${s("active")})
$$;
${userGrant(`${fn("list_booking_services")}(${ctx.idType}, boolean)`)}
`;
}
