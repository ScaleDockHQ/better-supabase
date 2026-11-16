-- ==== alone: schema supabase/schemas/900_better_supabase_039_announcements.sql
-- better-supabase module: announcements
-- @bsb-block announcements@1 managed
-- @bsb-hash sha256:3e79cb23a6dcaf63d5e12be2ade17f95cd5d3063324278585b96c0dde32135d9
-- In-app announcements for everyone, tenants, roles or plans within a time window, with per-user dismissals and a Realtime broadcast when they change. Staff manage them with announcements.manage on the platform.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Announcements staff publish to everyone, to tenants, to members with a
-- role, or (with entitlements) to tenants on a plan, between starts_at and
-- ends_at. targets holds the tenant ids, roles or plan lookup keys.
create table "better_supabase"."announcements" (
  "id" uuid primary key default gen_random_uuid(),
  "title" text not null constraint bsb_announcements_title_check check (length("title") >= 1 and length("title") <= 200),
  "body" text not null default '' constraint bsb_announcements_body_check check (length("body") <= 10000),
  "severity" text not null default 'info' constraint bsb_announcements_severity_check check ("severity" in ('info', 'success', 'warning', 'critical')),
  "href" text constraint bsb_announcements_href_check check ("href" ~ '^(https://|/)'),
  "audience" text not null default 'all',
  "targets" text[] not null default '{}',
  "starts_at" timestamptz not null default now(),
  "ends_at" timestamptz,
  "dismissible" boolean not null default true,
  "archived_at" timestamptz,
  "created_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  constraint bsb_announcements_check check ("ends_at" is null or "ends_at" > "starts_at"),
  constraint bsb_announcements_check1 check (("audience" = 'all') = (cardinality("targets") = 0))
);
-- The plan audience depends on the entitlements module, so a re-run replaces
-- the check.

alter table "better_supabase"."announcements" add constraint bsb_announcements_audience check ("audience" in ('all', 'tenant', 'role'));
create index announcements_window_idx on "better_supabase"."announcements" ("starts_at", "ends_at");
create index announcements_created_by_idx on "better_supabase"."announcements" ("created_by");
alter table "better_supabase"."announcements" enable row level security;
revoke all on "better_supabase"."announcements" from public, anon, authenticated;
grant all on "better_supabase"."announcements" to service_role;

create table "better_supabase"."announcement_dismissals" (
  "announcement_id" uuid not null references "better_supabase"."announcements" ("id") on delete cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "dismissed_at" timestamptz not null default now(),
  primary key ("announcement_id", "user_id")
);
create index announcement_dismissals_user_idx on "better_supabase"."announcement_dismissals" ("user_id");
alter table "better_supabase"."announcement_dismissals" enable row level security;
revoke all on "better_supabase"."announcement_dismissals" from public, anon, authenticated;
grant all on "better_supabase"."announcement_dismissals" to service_role;

-- The caller's live, undismissed announcements, newest first. Pass the
-- active tenant for tenant, role and plan audiences; a tenant the caller
-- isn't a member of counts as none.
create or replace function "better_supabase"."active_announcements"(tenant uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_tenant uuid := active_announcements.tenant;
  v_role text;
begin
  if v_tenant is not null then
    v_role := better_supabase.organization_member_role(v_tenant, v_user);
    if v_role is null and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
      v_tenant := null;
    end if;
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(x) - 'targets' order by x."starts_at" desc), '[]'::jsonb)
    from "better_supabase"."announcements" x
    where x."starts_at" <= now()
      and x."archived_at" is null
      and (x."ends_at" is null or x."ends_at" > now())
      and case x."audience"
        when 'all' then true
        when 'tenant' then v_tenant is not null and v_tenant::text = any (x."targets")
        when 'role' then v_role is not null and v_role = any (x."targets")
        
        else false
      end
      and not exists (
        select 1 from "better_supabase"."announcement_dismissals" s
        where s."announcement_id" = x."id" and s."user_id" = v_user
      )
  );
end;
$$;

-- Hides an announcement for the caller; false when it was hidden already.
create or replace function "better_supabase"."dismiss_announcement"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_dismissible boolean;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    raise exception 'Sign in first' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  select x."dismissible" into v_dismissible from "better_supabase"."announcements" x where x."id" = dismiss_announcement.id;
  if v_dismissible is null then
    raise exception 'No announcement %', dismiss_announcement.id using errcode = 'P0002', hint = 'ANNOUNCEMENT_NOT_FOUND';
  end if;
  if not v_dismissible then
    raise exception 'This announcement can''t be dismissed' using errcode = '22023', hint = 'ANNOUNCEMENT_NOT_DISMISSIBLE';
  end if;
  insert into "better_supabase"."announcement_dismissals" ("announcement_id", "user_id") values (dismiss_announcement.id, auth.uid())
  on conflict do nothing;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;

-- Every announcement, for staff (announcements.manage on the platform);
-- archived ones only with include_archived.
create or replace function "better_supabase"."list_announcements"(include_archived boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(x) order by x."starts_at" desc), '[]'::jsonb)
    from "better_supabase"."announcements" x
    where list_announcements.include_archived or x."archived_at" is null
  );
end;
$$;

-- Announcements as a keyset page for staff (announcements.manage on the
-- platform), newest start first (ADR 1077). filters is { severity, audience
-- (each a value or a list), archived (true adds archived ones), search (title,
-- body), sort (startsAt, title, createdAt), direction, facet, count, limit,
-- after, offset, paged, total, totalCap }.
create or replace function "better_supabase"."page_announcements"(filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_announcements.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('severity', 'audience') then
      raise exception 'facet is one of severity, audience' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
    end if;
    with s as (
      select (case v_facet when 'severity' then (x."severity")::text when 'audience' then (x."audience")::text end) as v
      from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('startsAt', 'title', 'createdAt') then
    raise exception 'sort is one of startsAt, title, createdAt' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."starts_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (x."starts_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."starts_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."starts_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (x."starts_at" <= (v_after ->> 0)::timestamptz and ((x."starts_at" < (v_after ->> 0)::timestamptz) or (x."starts_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."starts_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."starts_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (x."starts_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."starts_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."starts_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (x."starts_at" <= (v_after ->> 0)::timestamptz and ((x."starts_at" < (v_after ->> 0)::timestamptz) or (x."starts_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."starts_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (lower(x."title"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."title") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (lower(x."title") <= (v_after ->> 0)::text and ((lower(x."title") < (v_after ->> 0)::text) or (lower(x."title") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."title") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;

-- One announcement for staff, or null.
create or replace function "better_supabase"."get_announcement"(id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  return (
    select to_jsonb(x)
    from "better_supabase"."announcements" x where x."id" = get_announcement.id
  );
end;
$$;

-- Creates an announcement (id null) or changes one. fields holds the
-- columns to set; the others keep their value or default.
create or replace function "better_supabase"."save_announcement"(id uuid, fields jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."announcements";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  if save_announcement.id is null then
    v_row := jsonb_populate_record(null::"better_supabase"."announcements", jsonb_build_object(
      'id', gen_random_uuid(),
      'body', '',
      'severity', 'info',
      'audience', 'all',
      'targets', '{}'::text[],
      'starts_at', now(),
      'dismissible', true,
      'created_by', auth.uid(),
      'created_at', now()
    ) || save_announcement.fields);
    v_row."updated_at" := now();
    insert into "better_supabase"."announcements" select v_row.* returning * into v_row;
  else
    select * into v_row from "better_supabase"."announcements" x where x."id" = save_announcement.id for update;
    if v_row."id" is null then
      raise exception 'No announcement %', save_announcement.id using errcode = 'P0002', hint = 'ANNOUNCEMENT_NOT_FOUND';
    end if;
    v_row := jsonb_populate_record(v_row, save_announcement.fields - 'id' - 'archived_at' - 'created_by' - 'created_at');
    v_row."updated_at" := now();
    update "better_supabase"."announcements" x set ("title", "body", "severity", "href", "audience", "targets", "starts_at", "ends_at", "dismissible", "updated_at") = (v_row."title", v_row."body", v_row."severity", v_row."href", v_row."audience", v_row."targets", v_row."starts_at", v_row."ends_at", v_row."dismissible", v_row."updated_at")
    where x."id" = v_row."id"
    returning * into v_row;
  end if;
  if save_announcement.id is null then
    null;
  else
    null;
  end if;
  return to_jsonb(v_row);
end;
$$;

-- Archives an announcement: it stops showing and keeps its dismissals.
create or replace function "better_supabase"."archive_announcement"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."announcements";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."announcements" x where x."id" = archive_announcement.id for update;
  if v_row."id" is null then
    raise exception 'No announcement %', archive_announcement.id using errcode = 'P0002', hint = 'ANNOUNCEMENT_NOT_FOUND';
  end if;
  if v_row."archived_at" is not null then
    return to_jsonb(v_row);
  end if;
  update "better_supabase"."announcements" x set "archived_at" = now(), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return to_jsonb(v_row);
end;
$$;

-- Brings an archived announcement back, inside its window.
create or replace function "better_supabase"."restore_announcement"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."announcements";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."announcements" x where x."id" = restore_announcement.id for update;
  if v_row."id" is null then
    raise exception 'No announcement %', restore_announcement.id using errcode = 'P0002', hint = 'ANNOUNCEMENT_NOT_FOUND';
  end if;
  if v_row."archived_at" is null then
    return to_jsonb(v_row);
  end if;
  update "better_supabase"."announcements" x set "archived_at" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return to_jsonb(v_row);
end;
$$;

-- Removes an announcement and its dismissals for good. Archive keeps the row.
create or replace function "better_supabase"."purge_announcement"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  delete from "better_supabase"."announcements" x where x."id" = purge_announcement.id;
  get diagnostics v_count = row_count;
  if v_count > 0 then
    null;
  end if;
  return v_count > 0;
end;
$$;

-- Tells signed-in clients on the announcements topic that announcements changed;
-- they load the list again through active_announcements().
create or replace function "better_supabase"."broadcast_announcement"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(
      jsonb_build_object('id', coalesce(new."id", old."id"), 'operation', lower(tg_op)),
      'announcement_changed',
      'announcements',
      true
    );
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."broadcast_announcement"() from public, anon, authenticated;
create trigger "bsb_announcements_broadcast" after insert or update or delete on "better_supabase"."announcements"
  for each row execute function "better_supabase"."broadcast_announcement"();
create policy bsb_announcements_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension = 'broadcast' and (select realtime.topic()) = 'announcements');

revoke execute on function "better_supabase"."active_announcements"(uuid) from public, anon;
revoke execute on function "better_supabase"."dismiss_announcement"(uuid) from public, anon;
revoke execute on function "better_supabase"."list_announcements"(boolean) from public, anon;
revoke execute on function "better_supabase"."save_announcement"(uuid, jsonb) from public, anon;
revoke execute on function "better_supabase"."page_announcements"(jsonb) from public, anon;
revoke execute on function "better_supabase"."get_announcement"(uuid) from public, anon;
revoke execute on function "better_supabase"."archive_announcement"(uuid) from public, anon;
revoke execute on function "better_supabase"."restore_announcement"(uuid) from public, anon;
revoke execute on function "better_supabase"."purge_announcement"(uuid) from public, anon;
grant execute on function "better_supabase"."active_announcements"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."dismiss_announcement"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."list_announcements"(boolean) to authenticated, service_role;
grant execute on function "better_supabase"."save_announcement"(uuid, jsonb) to authenticated, service_role;
grant execute on function "better_supabase"."archive_announcement"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."restore_announcement"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."purge_announcement"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."page_announcements"(jsonb) to authenticated, service_role;
grant execute on function "better_supabase"."get_announcement"(uuid) to authenticated, service_role;

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_039_announcements.sql
-- better-supabase module: announcements
-- @bsb-block-data announcements
-- @bsb-hash sha256:60ebe88a3adfda6790a201adc72f29be4d50593ece2281d013078f8e48a2dc8d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('announcements', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_039_announcements.sql
-- better-supabase module: announcements
-- @bsb-block announcements@1 managed
-- @bsb-hash sha256:d3519330abae82012c27db64ef71a182397d212496855f05c43393d77301796e
-- In-app announcements for everyone, tenants, roles or plans within a time window, with per-user dismissals and a Realtime broadcast when they change. Staff manage them with announcements.manage on the platform.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Announcements staff publish to everyone, to tenants, to members with a
-- role, or (with entitlements) to tenants on a plan, between starts_at and
-- ends_at. targets holds the tenant ids, roles or plan lookup keys.
create table "better_supabase"."announcements" (
  "id" uuid primary key default gen_random_uuid(),
  "title" text not null constraint bsb_announcements_title_check check (length("title") >= 1 and length("title") <= 200),
  "body" text not null default '' constraint bsb_announcements_body_check check (length("body") <= 10000),
  "severity" text not null default 'info' constraint bsb_announcements_severity_check check ("severity" in ('info', 'success', 'warning', 'critical')),
  "href" text constraint bsb_announcements_href_check check ("href" ~ '^(https://|/)'),
  "audience" text not null default 'all',
  "targets" text[] not null default '{}',
  "starts_at" timestamptz not null default now(),
  "ends_at" timestamptz,
  "dismissible" boolean not null default true,
  "archived_at" timestamptz,
  "created_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  constraint bsb_announcements_check check ("ends_at" is null or "ends_at" > "starts_at"),
  constraint bsb_announcements_check1 check (("audience" = 'all') = (cardinality("targets") = 0))
);
-- The plan audience depends on the entitlements module, so a re-run replaces
-- the check.

alter table "better_supabase"."announcements" add constraint bsb_announcements_audience check ("audience" in ('all', 'tenant', 'role', 'plan'));
create index announcements_window_idx on "better_supabase"."announcements" ("starts_at", "ends_at");
create index announcements_created_by_idx on "better_supabase"."announcements" ("created_by");
alter table "better_supabase"."announcements" enable row level security;
revoke all on "better_supabase"."announcements" from public, anon, authenticated;
grant all on "better_supabase"."announcements" to service_role;

create table "better_supabase"."announcement_dismissals" (
  "announcement_id" uuid not null references "better_supabase"."announcements" ("id") on delete cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "dismissed_at" timestamptz not null default now(),
  primary key ("announcement_id", "user_id")
);
create index announcement_dismissals_user_idx on "better_supabase"."announcement_dismissals" ("user_id");
alter table "better_supabase"."announcement_dismissals" enable row level security;
revoke all on "better_supabase"."announcement_dismissals" from public, anon, authenticated;
grant all on "better_supabase"."announcement_dismissals" to service_role;

-- The caller's live, undismissed announcements, newest first. Pass the
-- active tenant for tenant, role and plan audiences; a tenant the caller
-- isn't a member of counts as none.
create or replace function "better_supabase"."active_announcements"(tenant uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_tenant uuid := active_announcements.tenant;
  v_role text;
begin
  if v_tenant is not null then
    v_role := better_supabase.organization_member_role(v_tenant, v_user);
    if v_role is null and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
      v_tenant := null;
    end if;
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(x) - 'targets' order by x."starts_at" desc), '[]'::jsonb)
    from "better_supabase"."announcements" x
    where x."starts_at" <= now()
      and x."archived_at" is null
      and (x."ends_at" is null or x."ends_at" > now())
      and case x."audience"
        when 'all' then true
        when 'tenant' then v_tenant is not null and v_tenant::text = any (x."targets")
        when 'role' then v_role is not null and v_role = any (x."targets")
        when 'plan' then v_tenant is not null and x."targets" && better_supabase.tenant_entitlements(v_tenant)
        else false
      end
      and not exists (
        select 1 from "better_supabase"."announcement_dismissals" s
        where s."announcement_id" = x."id" and s."user_id" = v_user
      )
  );
end;
$$;

-- Hides an announcement for the caller; false when it was hidden already.
create or replace function "better_supabase"."dismiss_announcement"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_dismissible boolean;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    raise exception 'Sign in first' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  select x."dismissible" into v_dismissible from "better_supabase"."announcements" x where x."id" = dismiss_announcement.id;
  if v_dismissible is null then
    raise exception 'No announcement %', dismiss_announcement.id using errcode = 'P0002', hint = 'ANNOUNCEMENT_NOT_FOUND';
  end if;
  if not v_dismissible then
    raise exception 'This announcement can''t be dismissed' using errcode = '22023', hint = 'ANNOUNCEMENT_NOT_DISMISSIBLE';
  end if;
  insert into "better_supabase"."announcement_dismissals" ("announcement_id", "user_id") values (dismiss_announcement.id, auth.uid())
  on conflict do nothing;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;

-- Every announcement, for staff (announcements.manage on the platform);
-- archived ones only with include_archived.
create or replace function "better_supabase"."list_announcements"(include_archived boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(x) order by x."starts_at" desc), '[]'::jsonb)
    from "better_supabase"."announcements" x
    where list_announcements.include_archived or x."archived_at" is null
  );
end;
$$;

-- Announcements as a keyset page for staff (announcements.manage on the
-- platform), newest start first (ADR 1077). filters is { severity, audience
-- (each a value or a list), archived (true adds archived ones), search (title,
-- body), sort (startsAt, title, createdAt), direction, facet, count, limit,
-- after, offset, paged, total, totalCap }.
create or replace function "better_supabase"."page_announcements"(filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_announcements.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('severity', 'audience') then
      raise exception 'facet is one of severity, audience' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
    end if;
    with s as (
      select (case v_facet when 'severity' then (x."severity")::text when 'audience' then (x."audience")::text end) as v
      from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('startsAt', 'title', 'createdAt') then
    raise exception 'sort is one of startsAt, title, createdAt' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."starts_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (x."starts_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."starts_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."starts_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (x."starts_at" <= (v_after ->> 0)::timestamptz and ((x."starts_at" < (v_after ->> 0)::timestamptz) or (x."starts_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."starts_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."starts_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (x."starts_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."starts_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."starts_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (x."starts_at" <= (v_after ->> 0)::timestamptz and ((x."starts_at" < (v_after ->> 0)::timestamptz) or (x."starts_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."starts_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (lower(x."title"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."title") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (lower(x."title") <= (v_after ->> 0)::text and ((lower(x."title") < (v_after ->> 0)::text) or (lower(x."title") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."title") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;

-- One announcement for staff, or null.
create or replace function "better_supabase"."get_announcement"(id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  return (
    select to_jsonb(x)
    from "better_supabase"."announcements" x where x."id" = get_announcement.id
  );
end;
$$;

-- Creates an announcement (id null) or changes one. fields holds the
-- columns to set; the others keep their value or default.
create or replace function "better_supabase"."save_announcement"(id uuid, fields jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."announcements";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  if save_announcement.id is null then
    v_row := jsonb_populate_record(null::"better_supabase"."announcements", jsonb_build_object(
      'id', gen_random_uuid(),
      'body', '',
      'severity', 'info',
      'audience', 'all',
      'targets', '{}'::text[],
      'starts_at', now(),
      'dismissible', true,
      'created_by', auth.uid(),
      'created_at', now()
    ) || save_announcement.fields);
    v_row."updated_at" := now();
    insert into "better_supabase"."announcements" select v_row.* returning * into v_row;
  else
    select * into v_row from "better_supabase"."announcements" x where x."id" = save_announcement.id for update;
    if v_row."id" is null then
      raise exception 'No announcement %', save_announcement.id using errcode = 'P0002', hint = 'ANNOUNCEMENT_NOT_FOUND';
    end if;
    v_row := jsonb_populate_record(v_row, save_announcement.fields - 'id' - 'archived_at' - 'created_by' - 'created_at');
    v_row."updated_at" := now();
    update "better_supabase"."announcements" x set ("title", "body", "severity", "href", "audience", "targets", "starts_at", "ends_at", "dismissible", "updated_at") = (v_row."title", v_row."body", v_row."severity", v_row."href", v_row."audience", v_row."targets", v_row."starts_at", v_row."ends_at", v_row."dismissible", v_row."updated_at")
    where x."id" = v_row."id"
    returning * into v_row;
  end if;
  if save_announcement.id is null then
    perform "better_supabase".emit_event('announcement.created', jsonb_build_object('announcementId', v_row."id"), 'announcements/' || v_row."id"::text, null, null, 'better-supabase/announcements');
  perform better_supabase.audit_event(
    event_type => 'announcement.created',
    category => 'configuration',
    target_type => 'announcement',
    record_id => v_row."id"::text,
    metadata => jsonb_build_object('announcementId', v_row."id")
  );
  else
    perform "better_supabase".emit_event('announcement.updated', jsonb_build_object('announcementId', v_row."id"), 'announcements/' || v_row."id"::text, null, null, 'better-supabase/announcements');
  perform better_supabase.audit_event(
    event_type => 'announcement.updated',
    category => 'configuration',
    target_type => 'announcement',
    record_id => v_row."id"::text,
    metadata => jsonb_build_object('announcementId', v_row."id")
  );
  end if;
  return to_jsonb(v_row);
end;
$$;

-- Archives an announcement: it stops showing and keeps its dismissals.
create or replace function "better_supabase"."archive_announcement"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."announcements";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."announcements" x where x."id" = archive_announcement.id for update;
  if v_row."id" is null then
    raise exception 'No announcement %', archive_announcement.id using errcode = 'P0002', hint = 'ANNOUNCEMENT_NOT_FOUND';
  end if;
  if v_row."archived_at" is not null then
    return to_jsonb(v_row);
  end if;
  update "better_supabase"."announcements" x set "archived_at" = now(), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('announcement.archived', jsonb_build_object('announcementId', v_row."id"), 'announcements/' || v_row."id"::text, null, null, 'better-supabase/announcements');
  perform better_supabase.audit_event(
    event_type => 'announcement.archived',
    category => 'configuration',
    target_type => 'announcement',
    record_id => v_row."id"::text,
    metadata => jsonb_build_object('announcementId', v_row."id")
  );
  return to_jsonb(v_row);
end;
$$;

-- Brings an archived announcement back, inside its window.
create or replace function "better_supabase"."restore_announcement"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."announcements";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."announcements" x where x."id" = restore_announcement.id for update;
  if v_row."id" is null then
    raise exception 'No announcement %', restore_announcement.id using errcode = 'P0002', hint = 'ANNOUNCEMENT_NOT_FOUND';
  end if;
  if v_row."archived_at" is null then
    return to_jsonb(v_row);
  end if;
  update "better_supabase"."announcements" x set "archived_at" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('announcement.restored', jsonb_build_object('announcementId', v_row."id"), 'announcements/' || v_row."id"::text, null, null, 'better-supabase/announcements');
  perform better_supabase.audit_event(
    event_type => 'announcement.restored',
    category => 'configuration',
    target_type => 'announcement',
    record_id => v_row."id"::text,
    metadata => jsonb_build_object('announcementId', v_row."id")
  );
  return to_jsonb(v_row);
end;
$$;

-- Removes an announcement and its dismissals for good. Archive keeps the row.
create or replace function "better_supabase"."purge_announcement"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  delete from "better_supabase"."announcements" x where x."id" = purge_announcement.id;
  get diagnostics v_count = row_count;
  if v_count > 0 then
    perform "better_supabase".emit_event('announcement.purged', jsonb_build_object('announcementId', purge_announcement.id), 'announcements/' || purge_announcement.id::text, null, null, 'better-supabase/announcements');
  perform better_supabase.audit_event(
    event_type => 'announcement.purged',
    category => 'configuration',
    target_type => 'announcement',
    record_id => purge_announcement.id::text,
    metadata => jsonb_build_object('announcementId', purge_announcement.id)
  );
  end if;
  return v_count > 0;
end;
$$;

-- Tells signed-in clients on the announcements topic that announcements changed;
-- they load the list again through active_announcements().
create or replace function "better_supabase"."broadcast_announcement"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(
      jsonb_build_object('id', coalesce(new."id", old."id"), 'operation', lower(tg_op)),
      'announcement_changed',
      'announcements',
      true
    );
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."broadcast_announcement"() from public, anon, authenticated;
create trigger "bsb_announcements_broadcast" after insert or update or delete on "better_supabase"."announcements"
  for each row execute function "better_supabase"."broadcast_announcement"();
create policy bsb_announcements_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension = 'broadcast' and (select realtime.topic()) = 'announcements');

revoke execute on function "better_supabase"."active_announcements"(uuid) from public, anon;
revoke execute on function "better_supabase"."dismiss_announcement"(uuid) from public, anon;
revoke execute on function "better_supabase"."list_announcements"(boolean) from public, anon;
revoke execute on function "better_supabase"."save_announcement"(uuid, jsonb) from public, anon;
revoke execute on function "better_supabase"."page_announcements"(jsonb) from public, anon;
revoke execute on function "better_supabase"."get_announcement"(uuid) from public, anon;
revoke execute on function "better_supabase"."archive_announcement"(uuid) from public, anon;
revoke execute on function "better_supabase"."restore_announcement"(uuid) from public, anon;
revoke execute on function "better_supabase"."purge_announcement"(uuid) from public, anon;
grant execute on function "better_supabase"."active_announcements"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."dismiss_announcement"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."list_announcements"(boolean) to authenticated, service_role;
grant execute on function "better_supabase"."save_announcement"(uuid, jsonb) to authenticated, service_role;
grant execute on function "better_supabase"."archive_announcement"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."restore_announcement"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."purge_announcement"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."page_announcements"(jsonb) to authenticated, service_role;
grant execute on function "better_supabase"."get_announcement"(uuid) to authenticated, service_role;

-- Row audit for the module's tables (blocks.audit.options.blockTables)
create constraint trigger bsb_audit after insert or update or delete on better_supabase.announcements deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"announcement","event_prefix":"announcement"}');

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_039_announcements.sql
-- better-supabase module: announcements
-- @bsb-block-data announcements
-- @bsb-hash sha256:60ebe88a3adfda6790a201adc72f29be4d50593ece2281d013078f8e48a2dc8d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('announcements', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_039_announcements.sql
-- better-supabase module: announcements
-- @bsb-block announcements@1 managed
-- @bsb-hash sha256:eeeb35e538256fb2f9dc8c2d97c555c56cb677565e8ba1f52c40d11a842a873f
-- In-app announcements for everyone, tenants, roles or plans within a time window, with per-user dismissals and a Realtime broadcast when they change. Staff manage them with announcements.manage on the platform.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;
-- Announcements staff publish to everyone, to tenants, to members with a
-- role, or (with entitlements) to tenants on a plan, between starts_at and
-- ends_at. targets holds the tenant ids, roles or plan lookup keys.
create table "app_private"."announcements" (
  "id" uuid primary key default gen_random_uuid(),
  "title" text not null constraint bsb_announcements_title_check check (length("title") >= 1 and length("title") <= 200),
  "body" text not null default '' constraint bsb_announcements_body_check check (length("body") <= 10000),
  "severity" text not null default 'info' constraint bsb_announcements_severity_check check ("severity" in ('info', 'success', 'warning', 'critical')),
  "href" text constraint bsb_announcements_href_check check ("href" ~ '^(https://|/)'),
  "audience" text not null default 'all',
  "targets" text[] not null default '{}',
  "starts_at" timestamptz not null default now(),
  "ends_at" timestamptz,
  "dismissible" boolean not null default true,
  "archived_at" timestamptz,
  "created_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  constraint bsb_announcements_check check ("ends_at" is null or "ends_at" > "starts_at"),
  constraint bsb_announcements_check1 check (("audience" = 'all') = (cardinality("targets") = 0))
);
-- The plan audience depends on the entitlements module, so a re-run replaces
-- the check.

alter table "app_private"."announcements" add constraint bsb_announcements_audience check ("audience" in ('all', 'tenant', 'role'));
create index announcements_window_idx on "app_private"."announcements" ("starts_at", "ends_at");
create index announcements_created_by_idx on "app_private"."announcements" ("created_by");
alter table "app_private"."announcements" enable row level security;
revoke all on "app_private"."announcements" from public, anon, authenticated;
grant all on "app_private"."announcements" to service_role;

create table "app_private"."announcement_dismissals" (
  "announcement_id" uuid not null references "app_private"."announcements" ("id") on delete cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "dismissed_at" timestamptz not null default now(),
  primary key ("announcement_id", "user_id")
);
create index announcement_dismissals_user_idx on "app_private"."announcement_dismissals" ("user_id");
alter table "app_private"."announcement_dismissals" enable row level security;
revoke all on "app_private"."announcement_dismissals" from public, anon, authenticated;
grant all on "app_private"."announcement_dismissals" to service_role;

-- The caller's live, undismissed announcements, newest first. Pass the
-- active tenant for tenant, role and plan audiences; a tenant the caller
-- isn't a member of counts as none.
create or replace function "app_private"."active_announcements"(tenant uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_tenant uuid := active_announcements.tenant;
  v_role text;
begin
  if v_tenant is not null then
    v_role := better_supabase.organization_member_role(v_tenant, v_user);
    if v_role is null and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
      v_tenant := null;
    end if;
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(x) - 'targets' order by x."starts_at" desc), '[]'::jsonb)
    from "app_private"."announcements" x
    where x."starts_at" <= now()
      and x."archived_at" is null
      and (x."ends_at" is null or x."ends_at" > now())
      and case x."audience"
        when 'all' then true
        when 'tenant' then v_tenant is not null and v_tenant::text = any (x."targets")
        when 'role' then v_role is not null and v_role = any (x."targets")
        
        else false
      end
      and not exists (
        select 1 from "app_private"."announcement_dismissals" s
        where s."announcement_id" = x."id" and s."user_id" = v_user
      )
  );
end;
$$;

-- Hides an announcement for the caller; false when it was hidden already.
create or replace function "app_private"."dismiss_announcement"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_dismissible boolean;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    raise exception 'Sign in first' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  select x."dismissible" into v_dismissible from "app_private"."announcements" x where x."id" = dismiss_announcement.id;
  if v_dismissible is null then
    raise exception 'No announcement %', dismiss_announcement.id using errcode = 'P0002', hint = 'ANNOUNCEMENT_NOT_FOUND';
  end if;
  if not v_dismissible then
    raise exception 'This announcement can''t be dismissed' using errcode = '22023', hint = 'ANNOUNCEMENT_NOT_DISMISSIBLE';
  end if;
  insert into "app_private"."announcement_dismissals" ("announcement_id", "user_id") values (dismiss_announcement.id, auth.uid())
  on conflict do nothing;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;

-- Every announcement, for staff (announcements.manage on the platform);
-- archived ones only with include_archived.
create or replace function "app_private"."list_announcements"(include_archived boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(x) order by x."starts_at" desc), '[]'::jsonb)
    from "app_private"."announcements" x
    where list_announcements.include_archived or x."archived_at" is null
  );
end;
$$;

-- Announcements as a keyset page for staff (announcements.manage on the
-- platform), newest start first (ADR 1077). filters is { severity, audience
-- (each a value or a list), archived (true adds archived ones), search (title,
-- body), sort (startsAt, title, createdAt), direction, facet, count, limit,
-- after, offset, paged, total, totalCap }.
create or replace function "app_private"."page_announcements"(filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_announcements.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('severity', 'audience') then
      raise exception 'facet is one of severity, audience' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
    end if;
    with s as (
      select (case v_facet when 'severity' then (x."severity")::text when 'audience' then (x."audience")::text end) as v
      from "app_private"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "app_private"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('startsAt', 'title', 'createdAt') then
    raise exception 'sort is one of startsAt, title, createdAt' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."starts_at")::text, (x."id")::text) as k
    from (
      select * from "app_private"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (x."starts_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."starts_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."starts_at")::text, (x."id")::text) as k
    from (
      select * from "app_private"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (x."starts_at" <= (v_after ->> 0)::timestamptz and ((x."starts_at" < (v_after ->> 0)::timestamptz) or (x."starts_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."starts_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."starts_at")::text, (x."id")::text) as k
    from (
      select * from "app_private"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (x."starts_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."starts_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."starts_at")::text, (x."id")::text) as k
    from (
      select * from "app_private"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (x."starts_at" <= (v_after ->> 0)::timestamptz and ((x."starts_at" < (v_after ->> 0)::timestamptz) or (x."starts_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."starts_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "app_private"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (lower(x."title"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."title") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "app_private"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (lower(x."title") <= (v_after ->> 0)::text and ((lower(x."title") < (v_after ->> 0)::text) or (lower(x."title") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."title") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "app_private"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "app_private"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "app_private"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;

-- One announcement for staff, or null.
create or replace function "app_private"."get_announcement"(id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  return (
    select to_jsonb(x)
    from "app_private"."announcements" x where x."id" = get_announcement.id
  );
end;
$$;

-- Creates an announcement (id null) or changes one. fields holds the
-- columns to set; the others keep their value or default.
create or replace function "app_private"."save_announcement"(id uuid, fields jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."announcements";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  if save_announcement.id is null then
    v_row := jsonb_populate_record(null::"app_private"."announcements", jsonb_build_object(
      'id', gen_random_uuid(),
      'body', '',
      'severity', 'info',
      'audience', 'all',
      'targets', '{}'::text[],
      'starts_at', now(),
      'dismissible', true,
      'created_by', auth.uid(),
      'created_at', now()
    ) || save_announcement.fields);
    v_row."updated_at" := now();
    insert into "app_private"."announcements" select v_row.* returning * into v_row;
  else
    select * into v_row from "app_private"."announcements" x where x."id" = save_announcement.id for update;
    if v_row."id" is null then
      raise exception 'No announcement %', save_announcement.id using errcode = 'P0002', hint = 'ANNOUNCEMENT_NOT_FOUND';
    end if;
    v_row := jsonb_populate_record(v_row, save_announcement.fields - 'id' - 'archived_at' - 'created_by' - 'created_at');
    v_row."updated_at" := now();
    update "app_private"."announcements" x set ("title", "body", "severity", "href", "audience", "targets", "starts_at", "ends_at", "dismissible", "updated_at") = (v_row."title", v_row."body", v_row."severity", v_row."href", v_row."audience", v_row."targets", v_row."starts_at", v_row."ends_at", v_row."dismissible", v_row."updated_at")
    where x."id" = v_row."id"
    returning * into v_row;
  end if;
  if save_announcement.id is null then
    null;
  else
    null;
  end if;
  return to_jsonb(v_row);
end;
$$;

-- Archives an announcement: it stops showing and keeps its dismissals.
create or replace function "app_private"."archive_announcement"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."announcements";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  select * into v_row from "app_private"."announcements" x where x."id" = archive_announcement.id for update;
  if v_row."id" is null then
    raise exception 'No announcement %', archive_announcement.id using errcode = 'P0002', hint = 'ANNOUNCEMENT_NOT_FOUND';
  end if;
  if v_row."archived_at" is not null then
    return to_jsonb(v_row);
  end if;
  update "app_private"."announcements" x set "archived_at" = now(), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return to_jsonb(v_row);
end;
$$;

-- Brings an archived announcement back, inside its window.
create or replace function "app_private"."restore_announcement"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."announcements";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  select * into v_row from "app_private"."announcements" x where x."id" = restore_announcement.id for update;
  if v_row."id" is null then
    raise exception 'No announcement %', restore_announcement.id using errcode = 'P0002', hint = 'ANNOUNCEMENT_NOT_FOUND';
  end if;
  if v_row."archived_at" is null then
    return to_jsonb(v_row);
  end if;
  update "app_private"."announcements" x set "archived_at" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return to_jsonb(v_row);
end;
$$;

-- Removes an announcement and its dismissals for good. Archive keeps the row.
create or replace function "app_private"."purge_announcement"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  delete from "app_private"."announcements" x where x."id" = purge_announcement.id;
  get diagnostics v_count = row_count;
  if v_count > 0 then
    null;
  end if;
  return v_count > 0;
end;
$$;

-- Tells signed-in clients on the announcements topic that announcements changed;
-- they load the list again through active_announcements().
create or replace function "app_private"."broadcast_announcement"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(
      jsonb_build_object('id', coalesce(new."id", old."id"), 'operation', lower(tg_op)),
      'announcement_changed',
      'announcements',
      true
    );
  end if;
  return null;
end;
$$;
revoke execute on function "app_private"."broadcast_announcement"() from public, anon, authenticated;
create trigger "bsb_announcements_broadcast" after insert or update or delete on "app_private"."announcements"
  for each row execute function "app_private"."broadcast_announcement"();
create policy bsb_announcements_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension = 'broadcast' and (select realtime.topic()) = 'announcements');

revoke execute on function "app_private"."active_announcements"(uuid) from public, anon;
revoke execute on function "app_private"."dismiss_announcement"(uuid) from public, anon;
revoke execute on function "app_private"."list_announcements"(boolean) from public, anon;
revoke execute on function "app_private"."save_announcement"(uuid, jsonb) from public, anon;
revoke execute on function "app_private"."page_announcements"(jsonb) from public, anon;
revoke execute on function "app_private"."get_announcement"(uuid) from public, anon;
revoke execute on function "app_private"."archive_announcement"(uuid) from public, anon;
revoke execute on function "app_private"."restore_announcement"(uuid) from public, anon;
revoke execute on function "app_private"."purge_announcement"(uuid) from public, anon;
grant execute on function "app_private"."active_announcements"(uuid) to authenticated, service_role;
grant execute on function "app_private"."dismiss_announcement"(uuid) to authenticated, service_role;
grant execute on function "app_private"."list_announcements"(boolean) to authenticated, service_role;
grant execute on function "app_private"."save_announcement"(uuid, jsonb) to authenticated, service_role;
grant execute on function "app_private"."archive_announcement"(uuid) to authenticated, service_role;
grant execute on function "app_private"."restore_announcement"(uuid) to authenticated, service_role;
grant execute on function "app_private"."purge_announcement"(uuid) to authenticated, service_role;
grant execute on function "app_private"."page_announcements"(jsonb) to authenticated, service_role;
grant execute on function "app_private"."get_announcement"(uuid) to authenticated, service_role;

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_039_announcements.sql
-- better-supabase module: announcements
-- @bsb-block-data announcements
-- @bsb-hash sha256:60ebe88a3adfda6790a201adc72f29be4d50593ece2281d013078f8e48a2dc8d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('announcements', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_039_announcements.sql
-- better-supabase module: announcements
-- @bsb-block announcements@1 managed
-- @bsb-hash sha256:47a4ff4c81ba867fdcc002be65dc1920078d350366b32ae47e8f7001791927b5
-- In-app announcements for everyone, tenants, roles or plans within a time window, with per-user dismissals and a Realtime broadcast when they change. Staff manage them with announcements.manage on the platform.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Announcements staff publish to everyone, to tenants, to members with a
-- role, or (with entitlements) to tenants on a plan, between starts_at and
-- ends_at. targets holds the tenant ids, roles or plan lookup keys.
create table "better_supabase"."announcements" (
  "id" uuid primary key default gen_random_uuid(),
  "title" text not null constraint bsb_announcements_title_check check (length("title") >= 1 and length("title") <= 200),
  "body" text not null default '' constraint bsb_announcements_body_check check (length("body") <= 10000),
  "severity" text not null default 'info' constraint bsb_announcements_severity_check check ("severity" in ('info', 'success', 'warning', 'critical')),
  "href" text constraint bsb_announcements_href_check check ("href" ~ '^(https://|/)'),
  "audience" text not null default 'all',
  "targets" text[] not null default '{}',
  "starts_at" timestamptz not null default now(),
  "ends_at" timestamptz,
  "dismissible" boolean not null default true,
  "archived_at" timestamptz,
  "created_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  constraint bsb_announcements_check check ("ends_at" is null or "ends_at" > "starts_at"),
  constraint bsb_announcements_check1 check (("audience" = 'all') = (cardinality("targets") = 0))
);
-- The plan audience depends on the entitlements module, so a re-run replaces
-- the check.

alter table "better_supabase"."announcements" add constraint bsb_announcements_audience check ("audience" in ('all', 'tenant', 'role'));
create index announcements_window_idx on "better_supabase"."announcements" ("starts_at", "ends_at");
create index announcements_created_by_idx on "better_supabase"."announcements" ("created_by");
alter table "better_supabase"."announcements" enable row level security;
revoke all on "better_supabase"."announcements" from public, anon, authenticated;
grant all on "better_supabase"."announcements" to service_role;

create table "better_supabase"."announcement_dismissals" (
  "announcement_id" uuid not null references "better_supabase"."announcements" ("id") on delete cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "dismissed_at" timestamptz not null default now(),
  primary key ("announcement_id", "user_id")
);
create index announcement_dismissals_user_idx on "better_supabase"."announcement_dismissals" ("user_id");
alter table "better_supabase"."announcement_dismissals" enable row level security;
revoke all on "better_supabase"."announcement_dismissals" from public, anon, authenticated;
grant all on "better_supabase"."announcement_dismissals" to service_role;

-- The caller's live, undismissed announcements, newest first. Pass the
-- active tenant for tenant, role and plan audiences; a tenant the caller
-- isn't a member of counts as none.
create or replace function "better_supabase"."active_announcements"(tenant uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_tenant uuid := active_announcements.tenant;
  v_role text;
begin
  if v_tenant is not null then
    v_role := better_supabase.organization_member_role(v_tenant, v_user);
    if v_role is null and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
      v_tenant := null;
    end if;
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(x) - 'targets' order by x."starts_at" desc), '[]'::jsonb)
    from "better_supabase"."announcements" x
    where x."starts_at" <= now()
      and x."archived_at" is null
      and (x."ends_at" is null or x."ends_at" > now())
      and case x."audience"
        when 'all' then true
        when 'tenant' then v_tenant is not null and v_tenant::text = any (x."targets")
        when 'role' then v_role is not null and v_role = any (x."targets")
        
        else false
      end
      and not exists (
        select 1 from "better_supabase"."announcement_dismissals" s
        where s."announcement_id" = x."id" and s."user_id" = v_user
      )
  );
end;
$$;

-- Hides an announcement for the caller; false when it was hidden already.
create or replace function "better_supabase"."dismiss_announcement"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_dismissible boolean;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    raise exception 'Sign in first' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  select x."dismissible" into v_dismissible from "better_supabase"."announcements" x where x."id" = dismiss_announcement.id;
  if v_dismissible is null then
    raise exception 'No announcement %', dismiss_announcement.id using errcode = 'P0002', hint = 'ANNOUNCEMENT_NOT_FOUND';
  end if;
  if not v_dismissible then
    raise exception 'This announcement can''t be dismissed' using errcode = '22023', hint = 'ANNOUNCEMENT_NOT_DISMISSIBLE';
  end if;
  insert into "better_supabase"."announcement_dismissals" ("announcement_id", "user_id") values (dismiss_announcement.id, auth.uid())
  on conflict do nothing;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;

-- Every announcement, for staff (announcements.manage on the platform);
-- archived ones only with include_archived.
create or replace function "better_supabase"."list_announcements"(include_archived boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(x) order by x."starts_at" desc), '[]'::jsonb)
    from "better_supabase"."announcements" x
    where list_announcements.include_archived or x."archived_at" is null
  );
end;
$$;

-- Announcements as a keyset page for staff (announcements.manage on the
-- platform), newest start first (ADR 1077). filters is { severity, audience
-- (each a value or a list), archived (true adds archived ones), search (title,
-- body), sort (startsAt, title, createdAt), direction, facet, count, limit,
-- after, offset, paged, total, totalCap }.
create or replace function "better_supabase"."page_announcements"(filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_announcements.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('severity', 'audience') then
      raise exception 'facet is one of severity, audience' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
    end if;
    with s as (
      select (case v_facet when 'severity' then (x."severity")::text when 'audience' then (x."audience")::text end) as v
      from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('startsAt', 'title', 'createdAt') then
    raise exception 'sort is one of startsAt, title, createdAt' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."starts_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (x."starts_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."starts_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."starts_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (x."starts_at" <= (v_after ->> 0)::timestamptz and ((x."starts_at" < (v_after ->> 0)::timestamptz) or (x."starts_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."starts_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."starts_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (x."starts_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."starts_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."starts_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (x."starts_at" <= (v_after ->> 0)::timestamptz and ((x."starts_at" < (v_after ->> 0)::timestamptz) or (x."starts_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."starts_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (lower(x."title"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."title") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (lower(x."title") <= (v_after ->> 0)::text and ((lower(x."title") < (v_after ->> 0)::text) or (lower(x."title") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."title") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;

-- One announcement for staff, or null.
create or replace function "better_supabase"."get_announcement"(id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  return (
    select to_jsonb(x)
    from "better_supabase"."announcements" x where x."id" = get_announcement.id
  );
end;
$$;

-- Creates an announcement (id null) or changes one. fields holds the
-- columns to set; the others keep their value or default.
create or replace function "better_supabase"."save_announcement"(id uuid, fields jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."announcements";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  if save_announcement.id is null then
    v_row := jsonb_populate_record(null::"better_supabase"."announcements", jsonb_build_object(
      'id', gen_random_uuid(),
      'body', '',
      'severity', 'info',
      'audience', 'all',
      'targets', '{}'::text[],
      'starts_at', now(),
      'dismissible', true,
      'created_by', auth.uid(),
      'created_at', now()
    ) || save_announcement.fields);
    v_row."updated_at" := now();
    insert into "better_supabase"."announcements" select v_row.* returning * into v_row;
  else
    select * into v_row from "better_supabase"."announcements" x where x."id" = save_announcement.id for update;
    if v_row."id" is null then
      raise exception 'No announcement %', save_announcement.id using errcode = 'P0002', hint = 'ANNOUNCEMENT_NOT_FOUND';
    end if;
    v_row := jsonb_populate_record(v_row, save_announcement.fields - 'id' - 'archived_at' - 'created_by' - 'created_at');
    v_row."updated_at" := now();
    update "better_supabase"."announcements" x set ("title", "body", "severity", "href", "audience", "targets", "starts_at", "ends_at", "dismissible", "updated_at") = (v_row."title", v_row."body", v_row."severity", v_row."href", v_row."audience", v_row."targets", v_row."starts_at", v_row."ends_at", v_row."dismissible", v_row."updated_at")
    where x."id" = v_row."id"
    returning * into v_row;
  end if;
  if save_announcement.id is null then
    null;
  else
    null;
  end if;
  return to_jsonb(v_row);
end;
$$;

-- Archives an announcement: it stops showing and keeps its dismissals.
create or replace function "better_supabase"."archive_announcement"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."announcements";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."announcements" x where x."id" = archive_announcement.id for update;
  if v_row."id" is null then
    raise exception 'No announcement %', archive_announcement.id using errcode = 'P0002', hint = 'ANNOUNCEMENT_NOT_FOUND';
  end if;
  if v_row."archived_at" is not null then
    return to_jsonb(v_row);
  end if;
  update "better_supabase"."announcements" x set "archived_at" = now(), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return to_jsonb(v_row);
end;
$$;

-- Brings an archived announcement back, inside its window.
create or replace function "better_supabase"."restore_announcement"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."announcements";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."announcements" x where x."id" = restore_announcement.id for update;
  if v_row."id" is null then
    raise exception 'No announcement %', restore_announcement.id using errcode = 'P0002', hint = 'ANNOUNCEMENT_NOT_FOUND';
  end if;
  if v_row."archived_at" is null then
    return to_jsonb(v_row);
  end if;
  update "better_supabase"."announcements" x set "archived_at" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return to_jsonb(v_row);
end;
$$;

-- Removes an announcement and its dismissals for good. Archive keeps the row.
create or replace function "better_supabase"."purge_announcement"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  delete from "better_supabase"."announcements" x where x."id" = purge_announcement.id;
  get diagnostics v_count = row_count;
  if v_count > 0 then
    null;
  end if;
  return v_count > 0;
end;
$$;

-- Tells signed-in clients on the announcements topic that announcements changed;
-- they load the list again through active_announcements().
create or replace function "better_supabase"."broadcast_announcement"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(
      jsonb_build_object('id', coalesce(new."id", old."id"), 'operation', lower(tg_op)),
      'announcement_changed',
      'announcements',
      true
    );
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."broadcast_announcement"() from public, anon, authenticated;
create trigger "bsb_announcements_broadcast" after insert or update or delete on "better_supabase"."announcements"
  for each row execute function "better_supabase"."broadcast_announcement"();
create policy bsb_announcements_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension = 'broadcast' and (select realtime.topic()) = 'announcements');

revoke execute on function "better_supabase"."active_announcements"(uuid) from public, anon;
revoke execute on function "better_supabase"."dismiss_announcement"(uuid) from public, anon;
revoke execute on function "better_supabase"."list_announcements"(boolean) from public, anon;
revoke execute on function "better_supabase"."save_announcement"(uuid, jsonb) from public, anon;
revoke execute on function "better_supabase"."page_announcements"(jsonb) from public, anon;
revoke execute on function "better_supabase"."get_announcement"(uuid) from public, anon;
revoke execute on function "better_supabase"."archive_announcement"(uuid) from public, anon;
revoke execute on function "better_supabase"."restore_announcement"(uuid) from public, anon;
revoke execute on function "better_supabase"."purge_announcement"(uuid) from public, anon;
grant execute on function "better_supabase"."active_announcements"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."dismiss_announcement"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."list_announcements"(boolean) to authenticated, service_role;
grant execute on function "better_supabase"."save_announcement"(uuid, jsonb) to authenticated, service_role;
grant execute on function "better_supabase"."archive_announcement"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."restore_announcement"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."purge_announcement"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."page_announcements"(jsonb) to authenticated, service_role;
grant execute on function "better_supabase"."get_announcement"(uuid) to authenticated, service_role;

-- blocks.announcements.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."active_announcements"(tenant uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."active_announcements"($1) $$;
revoke execute on function "api"."active_announcements"(uuid) from public, anon;
grant execute on function "api"."active_announcements"(uuid) to authenticated, service_role;

create or replace function "api"."dismiss_announcement"(id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."dismiss_announcement"($1) $$;
revoke execute on function "api"."dismiss_announcement"(uuid) from public, anon;
grant execute on function "api"."dismiss_announcement"(uuid) to authenticated, service_role;

create or replace function "api"."list_announcements"(include_archived boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_announcements"($1) $$;
revoke execute on function "api"."list_announcements"(boolean) from public, anon;
grant execute on function "api"."list_announcements"(boolean) to authenticated, service_role;

create or replace function "api"."save_announcement"(id uuid, fields jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_announcement"($1, $2) $$;
revoke execute on function "api"."save_announcement"(uuid, jsonb) from public, anon;
grant execute on function "api"."save_announcement"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."archive_announcement"(id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."archive_announcement"($1) $$;
revoke execute on function "api"."archive_announcement"(uuid) from public, anon;
grant execute on function "api"."archive_announcement"(uuid) to authenticated, service_role;

create or replace function "api"."restore_announcement"(id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."restore_announcement"($1) $$;
revoke execute on function "api"."restore_announcement"(uuid) from public, anon;
grant execute on function "api"."restore_announcement"(uuid) to authenticated, service_role;

create or replace function "api"."purge_announcement"(id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."purge_announcement"($1) $$;
revoke execute on function "api"."purge_announcement"(uuid) from public, anon;
grant execute on function "api"."purge_announcement"(uuid) to authenticated, service_role;

create or replace function "api"."page_announcements"(filters jsonb default '{}')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."page_announcements"($1) $$;
revoke execute on function "api"."page_announcements"(jsonb) from public, anon;
grant execute on function "api"."page_announcements"(jsonb) to authenticated, service_role;

create or replace function "api"."get_announcement"(id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."get_announcement"($1) $$;
revoke execute on function "api"."get_announcement"(uuid) from public, anon;
grant execute on function "api"."get_announcement"(uuid) to authenticated, service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_039_announcements.sql
-- better-supabase module: announcements
-- @bsb-block-data announcements
-- @bsb-hash sha256:60ebe88a3adfda6790a201adc72f29be4d50593ece2281d013078f8e48a2dc8d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('announcements', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_039_announcements.sql
-- better-supabase module: announcements
-- @bsb-block announcements@1 managed
-- @bsb-hash sha256:224bfc6b66e816627f92afb826d9bd17581ba75c716d6faafcc1b9f13e883c97
-- In-app announcements for everyone, tenants, roles or plans within a time window, with per-user dismissals and a Realtime broadcast when they change. Staff manage them with announcements.manage on the platform.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Announcements staff publish to everyone, to tenants, to members with a
-- role, or (with entitlements) to tenants on a plan, between starts_at and
-- ends_at. targets holds the tenant ids, roles or plan lookup keys.
-- better_supabase.announcements is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."announcements" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."announcements" add column if not exists "title" text constraint bsb_announcements_title_check check (length("title") >= 1 and length("title") <= 200);
alter table "better_supabase"."announcements" add column if not exists "body" text not null default '' constraint bsb_announcements_body_check check (length("body") <= 10000);
alter table "better_supabase"."announcements" add column if not exists "severity" text not null default 'info' constraint bsb_announcements_severity_check check ("severity" in ('info', 'success', 'warning', 'critical'));
alter table "better_supabase"."announcements" add column if not exists "href" text constraint bsb_announcements_href_check check ("href" ~ '^(https://|/)');
alter table "better_supabase"."announcements" add column if not exists "audience" text not null default 'all';
alter table "better_supabase"."announcements" add column if not exists "targets" text[] not null default '{}';
alter table "better_supabase"."announcements" add column if not exists "starts_at" timestamptz not null default now();
alter table "better_supabase"."announcements" add column if not exists "ends_at" timestamptz;
alter table "better_supabase"."announcements" add column if not exists "dismissible" boolean not null default true;
alter table "better_supabase"."announcements" add column if not exists "archived_at" timestamptz;
alter table "better_supabase"."announcements" add column if not exists "created_by" uuid references auth.users (id) on delete set null default auth.uid();
alter table "better_supabase"."announcements" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."announcements" add column if not exists "updated_at" timestamptz not null default now();
-- The plan audience depends on the entitlements module, so a re-run replaces
-- the check.
create index if not exists announcements_window_idx on "better_supabase"."announcements" ("starts_at", "ends_at");
create index if not exists announcements_created_by_idx on "better_supabase"."announcements" ("created_by");
alter table "better_supabase"."announcements" enable row level security;
grant all on "better_supabase"."announcements" to service_role;

-- better_supabase.announcement_dismissals is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."announcement_dismissals" add column if not exists "announcement_id" uuid references "better_supabase"."announcements" ("id") on delete cascade;
alter table "better_supabase"."announcement_dismissals" add column if not exists "user_id" uuid references auth.users (id) on delete cascade;
alter table "better_supabase"."announcement_dismissals" add column if not exists "dismissed_at" timestamptz not null default now();
create index if not exists announcement_dismissals_user_idx on "better_supabase"."announcement_dismissals" ("user_id");
create unique index if not exists "bsb_announcement_dismissals_key" on "better_supabase"."announcement_dismissals" ("announcement_id", "user_id");
alter table "better_supabase"."announcement_dismissals" enable row level security;
grant all on "better_supabase"."announcement_dismissals" to service_role;

-- The caller's live, undismissed announcements, newest first. Pass the
-- active tenant for tenant, role and plan audiences; a tenant the caller
-- isn't a member of counts as none.
create or replace function "better_supabase"."active_announcements"(tenant uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_tenant uuid := active_announcements.tenant;
  v_role text;
begin
  if v_tenant is not null then
    v_role := better_supabase.organization_member_role(v_tenant, v_user);
    if v_role is null and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
      v_tenant := null;
    end if;
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(x) - 'targets' order by x."starts_at" desc), '[]'::jsonb)
    from "better_supabase"."announcements" x
    where x."starts_at" <= now()
      and x."archived_at" is null
      and (x."ends_at" is null or x."ends_at" > now())
      and case x."audience"
        when 'all' then true
        when 'tenant' then v_tenant is not null and v_tenant::text = any (x."targets")
        when 'role' then v_role is not null and v_role = any (x."targets")
        
        else false
      end
      and not exists (
        select 1 from "better_supabase"."announcement_dismissals" s
        where s."announcement_id" = x."id" and s."user_id" = v_user
      )
  );
end;
$$;

-- Hides an announcement for the caller; false when it was hidden already.
create or replace function "better_supabase"."dismiss_announcement"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_dismissible boolean;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    raise exception 'Sign in first' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  select x."dismissible" into v_dismissible from "better_supabase"."announcements" x where x."id" = dismiss_announcement.id;
  if v_dismissible is null then
    raise exception 'No announcement %', dismiss_announcement.id using errcode = 'P0002', hint = 'ANNOUNCEMENT_NOT_FOUND';
  end if;
  if not v_dismissible then
    raise exception 'This announcement can''t be dismissed' using errcode = '22023', hint = 'ANNOUNCEMENT_NOT_DISMISSIBLE';
  end if;
  insert into "better_supabase"."announcement_dismissals" ("announcement_id", "user_id") values (dismiss_announcement.id, auth.uid())
  on conflict do nothing;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;

-- Every announcement, for staff (announcements.manage on the platform);
-- archived ones only with include_archived.
create or replace function "better_supabase"."list_announcements"(include_archived boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(x) order by x."starts_at" desc), '[]'::jsonb)
    from "better_supabase"."announcements" x
    where list_announcements.include_archived or x."archived_at" is null
  );
end;
$$;

-- Announcements as a keyset page for staff (announcements.manage on the
-- platform), newest start first (ADR 1077). filters is { severity, audience
-- (each a value or a list), archived (true adds archived ones), search (title,
-- body), sort (startsAt, title, createdAt), direction, facet, count, limit,
-- after, offset, paged, total, totalCap }.
create or replace function "better_supabase"."page_announcements"(filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_announcements.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('severity', 'audience') then
      raise exception 'facet is one of severity, audience' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
    end if;
    with s as (
      select (case v_facet when 'severity' then (x."severity")::text when 'audience' then (x."audience")::text end) as v
      from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('startsAt', 'title', 'createdAt') then
    raise exception 'sort is one of startsAt, title, createdAt' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."starts_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (x."starts_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."starts_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."starts_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (x."starts_at" <= (v_after ->> 0)::timestamptz and ((x."starts_at" < (v_after ->> 0)::timestamptz) or (x."starts_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."starts_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."starts_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (x."starts_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."starts_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."starts_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (x."starts_at" <= (v_after ->> 0)::timestamptz and ((x."starts_at" < (v_after ->> 0)::timestamptz) or (x."starts_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."starts_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (lower(x."title"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."title") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (lower(x."title") <= (v_after ->> 0)::text and ((lower(x."title") < (v_after ->> 0)::text) or (lower(x."title") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."title") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ANNOUNCEMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or (x."severity")::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or (x."audience")::text = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;

-- One announcement for staff, or null.
create or replace function "better_supabase"."get_announcement"(id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  return (
    select to_jsonb(x)
    from "better_supabase"."announcements" x where x."id" = get_announcement.id
  );
end;
$$;

-- Creates an announcement (id null) or changes one. fields holds the
-- columns to set; the others keep their value or default.
create or replace function "better_supabase"."save_announcement"(id uuid, fields jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."announcements";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  if save_announcement.id is null then
    v_row := jsonb_populate_record(null::"better_supabase"."announcements", jsonb_build_object(
      'id', gen_random_uuid(),
      'body', '',
      'severity', 'info',
      'audience', 'all',
      'targets', '{}'::text[],
      'starts_at', now(),
      'dismissible', true,
      'created_by', auth.uid(),
      'created_at', now()
    ) || save_announcement.fields);
    v_row."updated_at" := now();
    insert into "better_supabase"."announcements" ("id", "title", "body", "severity", "href", "audience", "targets", "starts_at", "ends_at", "dismissible", "archived_at", "created_by", "created_at", "updated_at") select v_row."id", v_row."title", v_row."body", v_row."severity", v_row."href", v_row."audience", v_row."targets", v_row."starts_at", v_row."ends_at", v_row."dismissible", v_row."archived_at", v_row."created_by", v_row."created_at", v_row."updated_at" returning * into v_row;
  else
    select * into v_row from "better_supabase"."announcements" x where x."id" = save_announcement.id for update;
    if v_row."id" is null then
      raise exception 'No announcement %', save_announcement.id using errcode = 'P0002', hint = 'ANNOUNCEMENT_NOT_FOUND';
    end if;
    v_row := jsonb_populate_record(v_row, save_announcement.fields - 'id' - 'archived_at' - 'created_by' - 'created_at');
    v_row."updated_at" := now();
    update "better_supabase"."announcements" x set ("title", "body", "severity", "href", "audience", "targets", "starts_at", "ends_at", "dismissible", "updated_at") = (v_row."title", v_row."body", v_row."severity", v_row."href", v_row."audience", v_row."targets", v_row."starts_at", v_row."ends_at", v_row."dismissible", v_row."updated_at")
    where x."id" = v_row."id"
    returning * into v_row;
  end if;
  if save_announcement.id is null then
    null;
  else
    null;
  end if;
  return to_jsonb(v_row);
end;
$$;

-- Archives an announcement: it stops showing and keeps its dismissals.
create or replace function "better_supabase"."archive_announcement"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."announcements";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."announcements" x where x."id" = archive_announcement.id for update;
  if v_row."id" is null then
    raise exception 'No announcement %', archive_announcement.id using errcode = 'P0002', hint = 'ANNOUNCEMENT_NOT_FOUND';
  end if;
  if v_row."archived_at" is not null then
    return to_jsonb(v_row);
  end if;
  update "better_supabase"."announcements" x set "archived_at" = now(), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return to_jsonb(v_row);
end;
$$;

-- Brings an archived announcement back, inside its window.
create or replace function "better_supabase"."restore_announcement"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."announcements";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."announcements" x where x."id" = restore_announcement.id for update;
  if v_row."id" is null then
    raise exception 'No announcement %', restore_announcement.id using errcode = 'P0002', hint = 'ANNOUNCEMENT_NOT_FOUND';
  end if;
  if v_row."archived_at" is null then
    return to_jsonb(v_row);
  end if;
  update "better_supabase"."announcements" x set "archived_at" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return to_jsonb(v_row);
end;
$$;

-- Removes an announcement and its dismissals for good. Archive keeps the row.
create or replace function "better_supabase"."purge_announcement"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  delete from "better_supabase"."announcements" x where x."id" = purge_announcement.id;
  get diagnostics v_count = row_count;
  if v_count > 0 then
    null;
  end if;
  return v_count > 0;
end;
$$;

-- Tells signed-in clients on the announcements topic that announcements changed;
-- they load the list again through active_announcements().
create or replace function "better_supabase"."broadcast_announcement"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(
      jsonb_build_object('id', coalesce(new."id", old."id"), 'operation', lower(tg_op)),
      'announcement_changed',
      'announcements',
      true
    );
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."broadcast_announcement"() from public, anon, authenticated;
create trigger "bsb_announcements_broadcast" after insert or update or delete on "better_supabase"."announcements"
  for each row execute function "better_supabase"."broadcast_announcement"();
create policy bsb_announcements_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension = 'broadcast' and (select realtime.topic()) = 'announcements');

revoke execute on function "better_supabase"."active_announcements"(uuid) from public, anon;
revoke execute on function "better_supabase"."dismiss_announcement"(uuid) from public, anon;
revoke execute on function "better_supabase"."list_announcements"(boolean) from public, anon;
revoke execute on function "better_supabase"."save_announcement"(uuid, jsonb) from public, anon;
revoke execute on function "better_supabase"."page_announcements"(jsonb) from public, anon;
revoke execute on function "better_supabase"."get_announcement"(uuid) from public, anon;
revoke execute on function "better_supabase"."archive_announcement"(uuid) from public, anon;
revoke execute on function "better_supabase"."restore_announcement"(uuid) from public, anon;
revoke execute on function "better_supabase"."purge_announcement"(uuid) from public, anon;
grant execute on function "better_supabase"."active_announcements"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."dismiss_announcement"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."list_announcements"(boolean) to authenticated, service_role;
grant execute on function "better_supabase"."save_announcement"(uuid, jsonb) to authenticated, service_role;
grant execute on function "better_supabase"."archive_announcement"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."restore_announcement"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."purge_announcement"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."page_announcements"(jsonb) to authenticated, service_role;
grant execute on function "better_supabase"."get_announcement"(uuid) to authenticated, service_role;

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_039_announcements.sql
-- better-supabase module: announcements
-- @bsb-block-data announcements
-- @bsb-hash sha256:60ebe88a3adfda6790a201adc72f29be4d50593ece2281d013078f8e48a2dc8d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('announcements', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
