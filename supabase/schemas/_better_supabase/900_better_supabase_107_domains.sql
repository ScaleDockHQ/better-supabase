-- better-supabase module: domains
-- @bsb-block domains@2 managed
-- @bsb-hash sha256:f3f705d3971968d6d42e4b7622df35cbe52fc95b991eec76c8699fa7b6d2298b
-- Hostnames an organization serves its app on: custom domains verified by a DNS TXT record, subdomains of the platform domain, one primary per organization, and resolve_hostname() for the proxy.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Hostnames an organization serves its app on: its own domains, verified by a
-- DNS TXT record _better-supabase.<hostname>, and subdomains of
-- blocks.domains.options.platformDomain (unset), verified when added. One organization holds
-- each verified hostname, and each organization has at most one primary.
create table "better_supabase"."hostnames" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "hostname" text not null constraint bsb_hostnames_hostname_check check (length("hostname") <= 253 and "hostname" ~ '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?[.])+[a-z]{2,63}$'),
  "kind" text not null default 'custom' constraint bsb_hostnames_kind_check check ("kind" in ('custom', 'subdomain')),
  "verification_token" text not null default replace(gen_random_uuid()::text, '-', ''),
  "verified_at" timestamptz,
  "is_primary" boolean not null default false,
  "created_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "hostname"),
  constraint bsb_hostnames_check check (not "is_primary" or "verified_at" is not null)
);
create unique index "hostnames_verified_idx" on "better_supabase"."hostnames" ("hostname") where "verified_at" is not null;
create unique index "hostnames_primary_idx" on "better_supabase"."hostnames" ("tenant_id") where "is_primary";
create index "hostnames_created_by_idx" on "better_supabase"."hostnames" ("created_by") where "created_by" is not null;
alter table "better_supabase"."hostnames" enable row level security;
revoke all on "better_supabase"."hostnames" from public, anon, authenticated;
grant all on "better_supabase"."hostnames" to service_role;

-- Adds a hostname (needs the manage permission). A custom domain comes back
-- with the TXT record to publish; adding it again returns the same row.
create or replace function "better_supabase"."add_hostname"(tenant uuid, hostname text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."hostnames";
  v_hostname text := lower(trim(trailing '.' from trim(add_hostname.hostname)));
  v_kind text := 'custom';
  v_label text;
  v_new boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', add_hostname.tenant, 'domains.manage'), false)) then
    raise exception 'You may not manage this organization''s hostnames' using errcode = '42501', hint = 'DOMAIN_FORBIDDEN';
  end if;
  if v_hostname is null or length(v_hostname) > 253 or v_hostname !~ '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?[.])+[a-z]{2,63}$' then
    raise exception 'Not a hostname: %', add_hostname.hostname using errcode = '22023', hint = 'DOMAIN_INVALID';
  end if;
  select * into v_row from "better_supabase"."hostnames" x where x."tenant_id" = add_hostname.tenant and x."hostname" = v_hostname;
  if v_row."id" is not null then
    return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
  end if;
  if v_kind = 'subdomain' and exists (select 1 from "better_supabase"."hostnames" x where x."hostname" = v_hostname and x."verified_at" is not null) then
    raise exception 'Another organization holds %', v_hostname using errcode = '23505', hint = 'DOMAIN_TAKEN';
  end if;
  insert into "better_supabase"."hostnames" ("tenant_id", "hostname", "kind", "verified_at")
  values (add_hostname.tenant, v_hostname, v_kind, case when v_kind = 'subdomain' then now() end)
  returning * into v_row;
  perform "better_supabase".emit_event('hostname.added', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'hostnameId', v_row."id"::text, 'hostname', v_row."hostname"), 'hostnames/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/domains');
  perform better_supabase.audit_event(
    event_type => 'hostname.added',
    category => 'configuration',
    target_type => 'hostname',
    record_id => v_row."id"::text,
    target_label => v_row."hostname",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'hostnameId', v_row."id"::text, 'hostname', v_row."hostname"),
    actor_id => auth.uid()
  );
  if v_row."verified_at" is not null then
    perform "better_supabase".emit_event('hostname.verified', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'hostnameId', v_row."id"::text, 'hostname', v_row."hostname"), 'hostnames/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/domains');
  perform better_supabase.audit_event(
    event_type => 'hostname.verified',
    category => 'configuration',
    target_type => 'hostname',
    record_id => v_row."id"::text,
    target_label => v_row."hostname",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'hostnameId', v_row."id"::text, 'hostname', v_row."hostname"),
    actor_id => auth.uid()
  );
  end if;
  return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
exception when unique_violation then
  raise exception 'Another organization holds %', v_hostname using errcode = '23505', hint = 'DOMAIN_TAKEN';
end;
$$;

-- An organization's hostnames, primary first (read permission or the service
-- role). filters is { kind, verified, sort, direction, facet, count, limit,
-- after, offset, paged, total, totalCap } (ADR 0749); verified takes true or
-- false.
create or replace function "better_supabase"."list_hostnames"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_hostnames.filters, '{}'::jsonb);
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 200), 1), 500);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_hostnames.tenant, 'domains.read'), false)) then
    raise exception 'You may not read this organization''s hostnames' using errcode = '42501', hint = 'DOMAIN_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'DOMAIN_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('kind', 'verified') then
      raise exception 'facet is one of kind, verified' using errcode = '22023', hint = 'DOMAIN_INVALID';
    end if;
    with s as (
      select (case v_facet when 'kind' then (x."kind")::text when 'verified' then ((x."verified_at" is not null))::text end) as v
      from "better_supabase"."hostnames" x
      where x."tenant_id" = list_hostnames.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'verified' is not null and jsonb_typeof(v_filters -> 'verified') <> 'null' and not (jsonb_typeof(v_filters -> 'verified') = 'array' and jsonb_array_length(v_filters -> 'verified') = 0)) or (x."verified_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'verified') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'verified')) else array[v_filters ->> 'verified'] end)::text[]))
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
      select 1 from "better_supabase"."hostnames" x
      where x."tenant_id" = list_hostnames.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'verified' is not null and jsonb_typeof(v_filters -> 'verified') <> 'null' and not (jsonb_typeof(v_filters -> 'verified') = 'array' and jsonb_array_length(v_filters -> 'verified') = 0)) or (x."verified_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'verified') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'verified')) else array[v_filters ->> 'verified'] end)::text[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('hostname', 'createdAt') then
    raise exception 'sort is one of hostname, createdAt' using errcode = '22023', hint = 'DOMAIN_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'DOMAIN_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DOMAIN_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (to_jsonb(x) - 'verification_token') || case when x."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || x."hostname", 'value', 'better-supabase-hostname-verification=' || x."verification_token")) else '{}'::jsonb end as j, jsonb_build_array((x."is_primary")::text, (x."hostname")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."hostnames" x
      where x."tenant_id" = list_hostnames.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'verified' is not null and jsonb_typeof(v_filters -> 'verified') <> 'null' and not (jsonb_typeof(v_filters -> 'verified') = 'array' and jsonb_array_length(v_filters -> 'verified') = 0)) or (x."verified_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'verified') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'verified')) else array[v_filters ->> 'verified'] end)::text[]))
        and (v_after is null or (x."is_primary", x."hostname", x."id") > ((v_after ->> 0)::boolean, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."is_primary" asc, x."hostname" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DOMAIN_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (to_jsonb(x) - 'verification_token') || case when x."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || x."hostname", 'value', 'better-supabase-hostname-verification=' || x."verification_token")) else '{}'::jsonb end as j, jsonb_build_array((x."is_primary")::text, (x."hostname")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."hostnames" x
      where x."tenant_id" = list_hostnames.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'verified' is not null and jsonb_typeof(v_filters -> 'verified') <> 'null' and not (jsonb_typeof(v_filters -> 'verified') = 'array' and jsonb_array_length(v_filters -> 'verified') = 0)) or (x."verified_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'verified') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'verified')) else array[v_filters ->> 'verified'] end)::text[]))
        and (v_after is null or (x."is_primary" <= (v_after ->> 0)::boolean and ((x."is_primary" < (v_after ->> 0)::boolean) or (x."is_primary" = (v_after ->> 0)::boolean and x."hostname" > (v_after ->> 1)::text) or (x."is_primary" = (v_after ->> 0)::boolean and x."hostname" = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."is_primary" desc, x."hostname" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'hostname' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DOMAIN_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (to_jsonb(x) - 'verification_token') || case when x."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || x."hostname", 'value', 'better-supabase-hostname-verification=' || x."verification_token")) else '{}'::jsonb end as j, jsonb_build_array((x."hostname")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."hostnames" x
      where x."tenant_id" = list_hostnames.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'verified' is not null and jsonb_typeof(v_filters -> 'verified') <> 'null' and not (jsonb_typeof(v_filters -> 'verified') = 'array' and jsonb_array_length(v_filters -> 'verified') = 0)) or (x."verified_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'verified') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'verified')) else array[v_filters ->> 'verified'] end)::text[]))
        and (v_after is null or (x."hostname", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."hostname" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'hostname' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DOMAIN_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (to_jsonb(x) - 'verification_token') || case when x."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || x."hostname", 'value', 'better-supabase-hostname-verification=' || x."verification_token")) else '{}'::jsonb end as j, jsonb_build_array((x."hostname")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."hostnames" x
      where x."tenant_id" = list_hostnames.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'verified' is not null and jsonb_typeof(v_filters -> 'verified') <> 'null' and not (jsonb_typeof(v_filters -> 'verified') = 'array' and jsonb_array_length(v_filters -> 'verified') = 0)) or (x."verified_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'verified') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'verified')) else array[v_filters ->> 'verified'] end)::text[]))
        and (v_after is null or (x."hostname" <= (v_after ->> 0)::text and ((x."hostname" < (v_after ->> 0)::text) or (x."hostname" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."hostname" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DOMAIN_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (to_jsonb(x) - 'verification_token') || case when x."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || x."hostname", 'value', 'better-supabase-hostname-verification=' || x."verification_token")) else '{}'::jsonb end as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."hostnames" x
      where x."tenant_id" = list_hostnames.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'verified' is not null and jsonb_typeof(v_filters -> 'verified') <> 'null' and not (jsonb_typeof(v_filters -> 'verified') = 'array' and jsonb_array_length(v_filters -> 'verified') = 0)) or (x."verified_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'verified') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'verified')) else array[v_filters ->> 'verified'] end)::text[]))
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DOMAIN_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (to_jsonb(x) - 'verification_token') || case when x."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || x."hostname", 'value', 'better-supabase-hostname-verification=' || x."verification_token")) else '{}'::jsonb end as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."hostnames" x
      where x."tenant_id" = list_hostnames.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'verified' is not null and jsonb_typeof(v_filters -> 'verified') <> 'null' and not (jsonb_typeof(v_filters -> 'verified') = 'array' and jsonb_array_length(v_filters -> 'verified') = 0)) or (x."verified_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'verified') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'verified')) else array[v_filters ->> 'verified'] end)::text[]))
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
      select 1 from "better_supabase"."hostnames" x
      where x."tenant_id" = list_hostnames.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'verified' is not null and jsonb_typeof(v_filters -> 'verified') <> 'null' and not (jsonb_typeof(v_filters -> 'verified') = 'array' and jsonb_array_length(v_filters -> 'verified') = 0)) or (x."verified_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'verified') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'verified')) else array[v_filters ->> 'verified'] end)::text[]))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;

-- One hostname with its record, for the service role or a manager; null otherwise.
create or replace function "better_supabase"."hostname_by_id"(id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."hostnames";
begin
  select * into v_row from "better_supabase"."hostnames" x where x."id" = hostname_by_id.id;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'domains.manage'), false)) then
    return null;
  end if;
  return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
end;
$$;

-- Marks a hostname verified once the app has found its TXT record (service
-- role only). `actor`, when set, must hold the manage permission.
create or replace function "better_supabase"."verify_hostname"(id uuid, actor uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."hostnames";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role verifies hostnames' using errcode = '42501', hint = 'DOMAIN_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."hostnames" x where x."id" = verify_hostname.id for update;
  if v_row."id" is null or not (verify_hostname.actor is null or coalesce(better_supabase.can_user(verify_hostname.actor, 'tenant', v_row."tenant_id", 'domains.manage'), false)) then
    raise exception 'No hostname you manage has this id' using errcode = 'P0002', hint = 'DOMAIN_NOT_FOUND';
  end if;
  if v_row."verified_at" is not null then
    return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
  end if;
  if exists (select 1 from "better_supabase"."hostnames" x where x."hostname" = v_row."hostname" and x."verified_at" is not null) then
    raise exception 'Another organization holds %', v_row."hostname" using errcode = '23505', hint = 'DOMAIN_TAKEN';
  end if;
  update "better_supabase"."hostnames" x set "verified_at" = now() where x."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('hostname.verified', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'hostnameId', v_row."id"::text, 'hostname', v_row."hostname"), 'hostnames/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/domains');
  perform better_supabase.audit_event(
    event_type => 'hostname.verified',
    category => 'configuration',
    target_type => 'hostname',
    record_id => v_row."id"::text,
    target_label => v_row."hostname",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'hostnameId', v_row."id"::text, 'hostname', v_row."hostname"),
    actor_id => verify_hostname.actor
  );
  return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
end;
$$;

-- Makes a verified hostname the organization's primary, the one other
-- hostnames redirect to.
create or replace function "better_supabase"."set_primary_hostname"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."hostnames";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."hostnames" x where x."id" = set_primary_hostname.id for update;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'domains.manage'), false)) then
    raise exception 'No hostname you manage has this id' using errcode = 'P0002', hint = 'DOMAIN_NOT_FOUND';
  end if;
  if v_row."verified_at" is null then
    raise exception 'Verify the hostname first' using errcode = '22023', hint = 'DOMAIN_NOT_VERIFIED';
  end if;
  if v_row."is_primary" then
    return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
  end if;
  update "better_supabase"."hostnames" x set "is_primary" = false where x."tenant_id" = v_row."tenant_id" and x."is_primary";
  update "better_supabase"."hostnames" x set "is_primary" = true where x."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('hostname.primary_changed', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'hostnameId', v_row."id"::text, 'hostname', v_row."hostname"), 'hostnames/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/domains');
  perform better_supabase.audit_event(
    event_type => 'hostname.primary_changed',
    category => 'configuration',
    target_type => 'hostname',
    record_id => v_row."id"::text,
    target_label => v_row."hostname",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'hostnameId', v_row."id"::text, 'hostname', v_row."hostname"),
    actor_id => auth.uid()
  );
  return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
end;
$$;

-- Removes a hostname; false when there is none the caller manages.
create or replace function "better_supabase"."remove_hostname"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."hostnames";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."hostnames" x where x."id" = remove_hostname.id;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'domains.manage'), false)) then
    return false;
  end if;
  delete from "better_supabase"."hostnames" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('hostname.deleted', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'hostnameId', v_row."id"::text, 'hostname', v_row."hostname"), 'hostnames/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/domains');
  perform better_supabase.audit_event(
    event_type => 'hostname.deleted',
    category => 'configuration',
    target_type => 'hostname',
    record_id => v_row."id"::text,
    target_label => v_row."hostname",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'hostnameId', v_row."id"::text, 'hostname', v_row."hostname"),
    actor_id => auth.uid()
  );
  return true;
end;
$$;

-- The organization a request's hostname belongs to, for the proxy: null
-- unless the hostname is verified. Open to anon, since the proxy runs before
-- sign-in; it returns nothing a DNS lookup doesn't already show.
create or replace function "better_supabase"."resolve_hostname"(hostname text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'organizationId', x."tenant_id",
    'hostname', x."hostname",
    'primary', x."is_primary",
    'primaryHostname', (
      select p."hostname" from "better_supabase"."hostnames" p
      where p."tenant_id" = x."tenant_id" and p."is_primary"
    )
  )
  from "better_supabase"."hostnames" x
  where x."hostname" = lower(trim(trailing '.' from trim(resolve_hostname.hostname)))
    and x."verified_at" is not null
$$;

revoke execute on function "better_supabase"."add_hostname"(uuid, text) from public, anon;
revoke execute on function "better_supabase"."list_hostnames"(uuid, jsonb) from public, anon;
revoke execute on function "better_supabase"."hostname_by_id"(uuid) from public, anon;
revoke execute on function "better_supabase"."verify_hostname"(uuid, uuid) from public, anon, authenticated;
revoke execute on function "better_supabase"."set_primary_hostname"(uuid) from public, anon;
revoke execute on function "better_supabase"."remove_hostname"(uuid) from public, anon;
revoke execute on function "better_supabase"."resolve_hostname"(text) from public;
grant execute on function "better_supabase"."add_hostname"(uuid, text) to authenticated, service_role;
grant execute on function "better_supabase"."list_hostnames"(uuid, jsonb) to authenticated, service_role;
grant execute on function "better_supabase"."hostname_by_id"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."verify_hostname"(uuid, uuid) to service_role;
grant execute on function "better_supabase"."set_primary_hostname"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."remove_hostname"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."resolve_hostname"(text) to anon, authenticated, service_role;

-- blocks.domains.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."add_hostname"(tenant uuid, hostname text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."add_hostname"($1, $2) $$;
revoke execute on function "api"."add_hostname"(uuid, text) from public, anon;
grant execute on function "api"."add_hostname"(uuid, text) to authenticated, service_role;

create or replace function "api"."list_hostnames"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_hostnames"($1, $2) $$;
revoke execute on function "api"."list_hostnames"(uuid, jsonb) from public, anon;
grant execute on function "api"."list_hostnames"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."hostname_by_id"(id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."hostname_by_id"($1) $$;
revoke execute on function "api"."hostname_by_id"(uuid) from public, anon;
grant execute on function "api"."hostname_by_id"(uuid) to authenticated, service_role;

create or replace function "api"."verify_hostname"(id uuid, actor uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."verify_hostname"($1, $2) $$;
revoke execute on function "api"."verify_hostname"(uuid, uuid) from public, anon, authenticated;
grant execute on function "api"."verify_hostname"(uuid, uuid) to service_role;

create or replace function "api"."set_primary_hostname"(id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_primary_hostname"($1) $$;
revoke execute on function "api"."set_primary_hostname"(uuid) from public, anon;
grant execute on function "api"."set_primary_hostname"(uuid) to authenticated, service_role;

create or replace function "api"."remove_hostname"(id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."remove_hostname"($1) $$;
revoke execute on function "api"."remove_hostname"(uuid) from public, anon;
grant execute on function "api"."remove_hostname"(uuid) to authenticated, service_role;

create or replace function "api"."resolve_hostname"(hostname text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."resolve_hostname"($1) $$;
revoke execute on function "api"."resolve_hostname"(text) from public;
grant execute on function "api"."resolve_hostname"(text) to anon, authenticated, service_role;
