-- ==== schema supabase/schemas/900_better_supabase_039_announcements.sql
-- better-supabase module: announcements
-- @bsb-block announcements@1 managed
-- @bsb-hash sha256:462537f387caaaa0e76a58b33e82558465d681f8f326106e0f2afd9947aaead4
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
    select coalesce(jsonb_agg((to_jsonb(x) - 'targets' || jsonb_build_object('fields', jsonb_build_object('app_note', x."app_note"))) order by x."starts_at" desc), '[]'::jsonb)
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
    select coalesce(jsonb_agg((to_jsonb(x) || jsonb_build_object('fields', jsonb_build_object('app_note', x."app_note"))) order by x."starts_at" desc), '[]'::jsonb)
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
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or x."severity" = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or x."audience" = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
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
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or x."severity" = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or x."audience" = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
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
    select row_number() over () as n, (to_jsonb(x) || jsonb_build_object('fields', jsonb_build_object('app_note', x."app_note"))) as j, jsonb_build_array((x."starts_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or x."severity" = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or x."audience" = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
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
    select row_number() over () as n, (to_jsonb(x) || jsonb_build_object('fields', jsonb_build_object('app_note', x."app_note"))) as j, jsonb_build_array((x."starts_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or x."severity" = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or x."audience" = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
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
    select row_number() over () as n, (to_jsonb(x) || jsonb_build_object('fields', jsonb_build_object('app_note', x."app_note"))) as j, jsonb_build_array((x."starts_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or x."severity" = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or x."audience" = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
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
    select row_number() over () as n, (to_jsonb(x) || jsonb_build_object('fields', jsonb_build_object('app_note', x."app_note"))) as j, jsonb_build_array((x."starts_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or x."severity" = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or x."audience" = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
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
    select row_number() over () as n, (to_jsonb(x) || jsonb_build_object('fields', jsonb_build_object('app_note', x."app_note"))) as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or x."severity" = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or x."audience" = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
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
    select row_number() over () as n, (to_jsonb(x) || jsonb_build_object('fields', jsonb_build_object('app_note', x."app_note"))) as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or x."severity" = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or x."audience" = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
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
    select row_number() over () as n, (to_jsonb(x) || jsonb_build_object('fields', jsonb_build_object('app_note', x."app_note"))) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or x."severity" = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or x."audience" = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
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
    select row_number() over () as n, (to_jsonb(x) || jsonb_build_object('fields', jsonb_build_object('app_note', x."app_note"))) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."announcements" x
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or x."severity" = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or x."audience" = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
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
      where (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or x."severity" = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'audience' is not null and jsonb_typeof(v_filters -> 'audience') <> 'null' and not (jsonb_typeof(v_filters -> 'audience') = 'array' and jsonb_array_length(v_filters -> 'audience') = 0)) or x."audience" = any((case when jsonb_typeof(v_filters -> 'audience') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'audience')) else array[v_filters ->> 'audience'] end)::text[]))
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
    select (to_jsonb(x) || jsonb_build_object('fields', jsonb_build_object('app_note', x."app_note")))
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
    update "better_supabase"."announcements" x set ("title", "body", "severity", "href", "audience", "targets", "starts_at", "ends_at", "dismissible", "updated_at", "app_note") = (v_row."title", v_row."body", v_row."severity", v_row."href", v_row."audience", v_row."targets", v_row."starts_at", v_row."ends_at", v_row."dismissible", v_row."updated_at", v_row."app_note")
    where x."id" = v_row."id"
    returning * into v_row;
  end if;
  if save_announcement.id is null then
    null;
  else
    null;
  end if;
  return (to_jsonb(v_row) || jsonb_build_object('fields', jsonb_build_object('app_note', v_row."app_note")));
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
    return (to_jsonb(v_row) || jsonb_build_object('fields', jsonb_build_object('app_note', v_row."app_note")));
  end if;
  update "better_supabase"."announcements" x set "archived_at" = now(), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return (to_jsonb(v_row) || jsonb_build_object('fields', jsonb_build_object('app_note', v_row."app_note")));
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
    return (to_jsonb(v_row) || jsonb_build_object('fields', jsonb_build_object('app_note', v_row."app_note")));
  end if;
  update "better_supabase"."announcements" x set "archived_at" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return (to_jsonb(v_row) || jsonb_build_object('fields', jsonb_build_object('app_note', v_row."app_note")));
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

-- ==== data supabase/better-supabase-data/900_better_supabase_039_announcements.sql
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
