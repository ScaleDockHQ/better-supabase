import type { BlockSqlContext } from "../context.ts";

import { fail, SERVICE_CALLER, userGrant } from "../shared.ts";
import { COMPONENT_STATUSES } from "./incidents-shared.ts";
import { moduleOperations } from "./permissions-model.ts";

const list = (values: readonly string[]): string =>
  values.map((value) => `'${value}'`).join(", ");

/**
 * The status page functions. public_status_page is the only incidents function
 * anon may call (ADR 0084): it returns the fields named below and nothing else,
 * for published pages only.
 */
export function statusPageFunctions(ctx: BlockSqlContext): string {
  const components = ctx.table("components");
  const history = ctx.table("history");
  const incidents = ctx.table("incidents");
  const updates = ctx.table("updates");
  const impacts = ctx.table("impacts");
  const postmortems = ctx.table("postmortems");
  const pages = ctx.table("pages");
  const c = (column: string): string => ctx.col("components", column);
  const h = (column: string): string => ctx.col("history", column);
  const i = (column: string): string => ctx.col("incidents", column);
  const u = (column: string): string => ctx.col("updates", column);
  const m = (column: string): string => ctx.col("impacts", column);
  const pm = (column: string): string => ctx.col("postmortems", column);
  const g = (column: string): string => ctx.col("pages", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;

  const manage = ctx.permission("manage", moduleOperations("incidents").manage);

  const ranks = `array[${list(COMPONENT_STATUSES)}]`;

  const pageJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${g("id")}, 'organizationId', ${row}.${g("tenant")}, 'slug', ${row}.${g("slug")}, 'title', ${row}.${g("title")}, 'description', ${row}.${g("description")}, 'published', ${row}.${g("published")}, 'createdAt', ${row}.${g("createdAt")}, 'updatedAt', ${row}.${g("updatedAt")})`;

  // A public incident as the status page shows it: no description, no
  // commander, no private updates, and only the public components it affects.
  const publicIncident = (row: string): string =>
    `jsonb_build_object(
      'id', ${row}.${i("id")},
      'title', ${row}.${i("title")},
      'severity', ${row}.${i("severity")},
      'status', ${row}.${i("status")},
      'startedAt', ${row}.${i("startedAt")},
      'resolvedAt', ${row}.${i("resolvedAt")},
      'components', (
        select coalesce(jsonb_agg(jsonb_build_object('id', pc.${c("id")}, 'name', pc.${c("name")}, 'impact', pi.${m("impact")}) order by pc.${c("position")}, pc.${c("name")}), '[]'::jsonb)
        from ${impacts} pi join ${components} pc on pc.${c("id")} = pi.${m("component")}
        where pi.${m("incident")} = ${row}.${i("id")} and pc.${c("public")}
      ),
      'updates', (
        select coalesce(jsonb_agg(jsonb_build_object('status', pu.${u("status")}, 'body', pu.${u("body")}, 'createdAt', pu.${u("createdAt")}) order by pu.${u("createdAt")} desc), '[]'::jsonb)
        from ${updates} pu
        where pu.${u("incident")} = ${row}.${i("id")} and pu.${u("public")}
      ),
      'postmortem', (
        select jsonb_build_object('summary', pp.${pm("summary")}, 'publishedAt', pp.${pm("publishedAt")})
        from ${postmortems} pp
        where pp.${pm("incident")} = ${row}.${i("id")} and pp.${pm("status")} = 'published'
      )
    )`;

  return `
-- Creates or changes the organization's status page. A slug another
-- organization uses fails with STATUS_PAGE_SLUG_TAKEN.
create or replace function ${fn("save_status_page")}(tenant ${idType}, slug text, title text, description text default null, published boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${pages}%rowtype;
begin
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", "save_status_page.tenant", manage)}) then
    ${fail("INCIDENTS_FORBIDDEN", "not allowed to manage the status page")}
  end if;
  if save_status_page.slug is null or save_status_page.slug !~ '^[a-z0-9][a-z0-9-]{1,62}$' then
    ${fail("INCIDENTS_INVALID", "the slug takes 2 to 63 lowercase letters, digits and dashes", "22023")}
  end if;
  if exists (
    select 1 from ${pages} x where x.${g("slug")} = save_status_page.slug and x.${g("tenant")} <> save_status_page.tenant
  ) then
    ${fail("STATUS_PAGE_SLUG_TAKEN", "another organization uses this slug", "23505")}
  end if;
  insert into ${pages} (${g("tenant")}, ${g("slug")}, ${g("title")}, ${g("description")}, ${g("published")})
  values (save_status_page.tenant, save_status_page.slug, trim(save_status_page.title), save_status_page.description, coalesce(save_status_page.published, false))
  on conflict (${g("tenant")}) do update
    set ${g("slug")} = excluded.${g("slug")}, ${g("title")} = excluded.${g("title")}, ${g("description")} = excluded.${g("description")},
      ${g("published")} = excluded.${g("published")}, ${g("updatedAt")} = now()
  returning * into v_row;
  return ${pageJson("v_row")};
end;
$$;
${userGrant(`${fn("save_status_page")}(${idType}, text, text, text, boolean)`)}

create or replace function ${fn("get_status_page")}(tenant ${idType})
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select ${pageJson("x")} from ${pages} x where x.${g("tenant")} = get_status_page.tenant
$$;
${userGrant(`${fn("get_status_page")}(${idType})`)}

-- The public status page behind a slug, for anyone: null unless the page is
-- published. It returns the page title and description, the public
-- components with their status and daily uptime over days (1 to 90, default
-- 90), and the public incidents (open ones, and those resolved in the
-- window) with their public updates and published postmortem summary.
create or replace function ${fn("public_status_page")}(slug text, days integer default 90)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_page ${pages}%rowtype;
  v_days integer := least(greatest(coalesce(public_status_page.days, 90), 1), 90);
  v_from timestamptz;
begin
  select * into v_page from ${pages} x where x.${g("slug")} = public_status_page.slug and x.${g("published")};
  if not found then
    return null;
  end if;
  v_from := (current_date - (v_days - 1))::timestamp at time zone 'UTC';
  return jsonb_build_object(
    'slug', v_page.${g("slug")},
    'title', v_page.${g("title")},
    'description', v_page.${g("description")},
    'days', v_days,
    'status', (
      select coalesce((${ranks})[max(array_position(${ranks}, sc.${c("status")}))], 'operational')
      from ${components} sc
      where sc.${c("tenant")} = v_page.${g("tenant")} and sc.${c("public")}
    ),
    'components', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', pc.${c("id")},
        'name', pc.${c("name")},
        'description', pc.${c("description")},
        'group', pc.${c("group")},
        'status', pc.${c("status")},
        'uptimePercent', (
          select round(100 * (1 - coalesce(sum(extract(epoch from (
            least(coalesce(uh.${h("endedAt")}, now()), now()) - greatest(uh.${h("startedAt")}, v_from)
          ))), 0) / greatest(extract(epoch from (now() - v_from)), 1))::numeric, 3)
          from ${history} uh
          where uh.${h("component")} = pc.${c("id")}
            and uh.${h("status")} in ('partial_outage', 'major_outage')
            and coalesce(uh.${h("endedAt")}, now()) > v_from
        ),
        'uptime', (
          select jsonb_agg(jsonb_build_object('date', dd.d, 'status', coalesce(w.worst, 'operational'), 'downMinutes', coalesce(w.down, 0)) order by dd.d)
          from (select (current_date - n)::date as d from generate_series(0, v_days - 1) n) dd
          cross join lateral (
            select (${ranks})[max(array_position(${ranks}, dh.${h("status")}))] as worst,
              (coalesce(sum(extract(epoch from (
                least(coalesce(dh.${h("endedAt")}, now()), (dd.d + 1)::timestamp at time zone 'UTC')
                - greatest(dh.${h("startedAt")}, dd.d::timestamp at time zone 'UTC')
              ))) filter (where dh.${h("status")} in ('partial_outage', 'major_outage')), 0) / 60)::integer as down
            from ${history} dh
            where dh.${h("component")} = pc.${c("id")}
              and dh.${h("startedAt")} < (dd.d + 1)::timestamp at time zone 'UTC'
              and coalesce(dh.${h("endedAt")}, now()) > dd.d::timestamp at time zone 'UTC'
          ) w
        )
      ) order by pc.${c("position")}, pc.${c("name")}), '[]'::jsonb)
      from ${components} pc
      where pc.${c("tenant")} = v_page.${g("tenant")} and pc.${c("public")}
    ),
    'incidents', (
      select coalesce(jsonb_agg(${publicIncident("pi0")} order by pi0.${i("startedAt")} desc), '[]'::jsonb)
      from ${incidents} pi0
      where pi0.${i("tenant")} = v_page.${g("tenant")} and pi0.${i("public")}
        and (pi0.${i("resolvedAt")} is null or pi0.${i("resolvedAt")} >= v_from)
    )
  );
end;
$$;
revoke all on function ${fn("public_status_page")}(text, integer) from public, anon, authenticated;
grant execute on function ${fn("public_status_page")}(text, integer) to anon, authenticated, service_role;
`;
}
