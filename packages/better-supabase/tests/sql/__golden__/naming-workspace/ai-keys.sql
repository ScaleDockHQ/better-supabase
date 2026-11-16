-- ==== schema supabase/schemas/900_better_supabase_056_ai_keys.sql
-- better-supabase module: ai-keys
-- @bsb-block ai-keys@2 managed
-- @bsb-hash sha256:a0a57006bf5c8f279800e4ffd54ef932274be1970ca455f38f1e5c9f1a8e0811
-- A tenant's own provider keys as credential_ref rows, and a registry of provider batch jobs with their results and a poll claim. Sandboxes live in ai-chat.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- A tenant's own provider keys (BYOK). credential_ref names the key in a
-- CredentialProvider, such as Vault; the key itself is never stored here.
-- settings holds the provider's other options (a region, a project id) and
-- must not hold secrets.
create table "better_supabase"."ai_provider_keys" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "provider" text not null constraint bsb_ai_provider_keys_provider_check check ("provider" ~ '^[a-z0-9][a-z0-9._-]{0,63}$'),
  "name" text not null default 'default' constraint bsb_ai_provider_keys_name_check check (length("name") >= 1 and length("name") <= 100),
  "credential_ref" jsonb not null constraint bsb_ai_provider_keys_credential_ref_check check (jsonb_typeof("credential_ref") = 'object' and "credential_ref" ? 'provider'),
  "settings" jsonb not null default '{}' constraint bsb_ai_provider_keys_settings_check check (jsonb_typeof("settings") = 'object'),
  "enabled" boolean not null default true,
  "created_by" uuid references auth.users (id) on delete set null,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "provider", "name")
);
create index ai_provider_keys_created_by_idx on "better_supabase"."ai_provider_keys" ("created_by");
alter table "better_supabase"."ai_provider_keys" enable row level security;
revoke all on "better_supabase"."ai_provider_keys" from public, anon, authenticated;
grant select on "better_supabase"."ai_provider_keys" to authenticated;
grant all on "better_supabase"."ai_provider_keys" to service_role;
create policy bsb_ai_provider_keys_read on "better_supabase"."ai_provider_keys"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('ai_keys.manage')));

-- Batch jobs started with a provider's batch API, polled until they finish.
-- reference is the SDK's batch reference ({ version, id, provider }).
create table "better_supabase"."ai_batches" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid references auth.users (id) on delete cascade,
  "provider" text not null constraint bsb_ai_batches_provider_check check (length("provider") >= 1 and length("provider") <= 100),
  "reference" jsonb not null constraint bsb_ai_batches_reference_check check (jsonb_typeof("reference") = 'object'),
  "status" text not null default 'pending' constraint bsb_ai_batches_status_check check ("status" in ('pending', 'completed', 'failed', 'cancelled')),
  "raw_status" text constraint bsb_ai_batches_raw_status_check check (length("raw_status") <= 100),
  "item_count" integer not null default 0 constraint bsb_ai_batches_item_count_check check ("item_count" >= 0),
  "counts" jsonb not null default '{}' constraint bsb_ai_batches_counts_check check (jsonb_typeof("counts") = 'object'),
  "error" text constraint bsb_ai_batches_error_check check (length("error") <= 4000),
  "metadata" jsonb not null default '{}' constraint bsb_ai_batches_metadata_check check (jsonb_typeof("metadata") = 'object'),
  "results_saved" boolean not null default false,
  "polls" integer not null default 0,
  "next_poll_at" timestamptz default now(),
  "expires_at" timestamptz,
  "completed_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index ai_batches_due_idx on "better_supabase"."ai_batches" ("next_poll_at") where "status" = 'pending' or not "results_saved";
create index ai_batches_tenant_idx on "better_supabase"."ai_batches" ("tenant_id", "created_at" desc, "id" desc);
create index ai_batches_user_idx on "better_supabase"."ai_batches" ("user_id");
alter table "better_supabase"."ai_batches" enable row level security;
revoke all on "better_supabase"."ai_batches" from public, anon, authenticated;
grant select on "better_supabase"."ai_batches" to authenticated;
grant all on "better_supabase"."ai_batches" to service_role;
create policy bsb_ai_batches_read on "better_supabase"."ai_batches"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('ai_keys.manage')));

create table "better_supabase"."ai_batch_items" (
  "batch_id" uuid not null references "better_supabase"."ai_batches" ("id") on delete cascade,
  "request_id" text not null constraint bsb_ai_batch_items_request_id_check check (length("request_id") >= 1 and length("request_id") <= 200),
  "tenant_id" uuid not null,
  "status" text not null constraint bsb_ai_batch_items_status_check check ("status" in ('succeeded', 'failed', 'cancelled', 'expired')),
  "output" jsonb,
  "usage" jsonb,
  "error" text constraint bsb_ai_batch_items_error_check check (length("error") <= 4000),
  "created_at" timestamptz not null default now(),
  primary key ("batch_id", "request_id")
);
create index ai_batch_items_tenant_idx on "better_supabase"."ai_batch_items" ("tenant_id");
alter table "better_supabase"."ai_batch_items" enable row level security;
revoke all on "better_supabase"."ai_batch_items" from public, anon, authenticated;
grant select on "better_supabase"."ai_batch_items" to authenticated;
grant all on "better_supabase"."ai_batch_items" to service_role;
create policy bsb_ai_batch_items_read on "better_supabase"."ai_batch_items"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."ai_batches" y where y."id" = "batch_id"));

create or replace function "better_supabase"."list_ai_provider_keys"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'provider', x."provider", 'name', x."name", 'credential_ref', x."credential_ref", 'settings', x."settings", 'enabled', x."enabled", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") order by x."provider", x."name"), '[]')
  from "better_supabase"."ai_provider_keys" x where x."tenant_id" = list_ai_provider_keys.tenant
$$;
revoke execute on function "better_supabase"."list_ai_provider_keys"(uuid) from public, anon;
grant execute on function "better_supabase"."list_ai_provider_keys"(uuid) to authenticated, service_role;

-- The tenant's provider keys as a keyset page (ADR 1077), by provider and
-- name. filters is { provider, enabled (a value or a list), search (provider,
-- name), sort (provider, name, createdAt), direction, facet, count, limit,
-- after, offset, paged, total, totalCap }.
create or replace function "better_supabase"."page_ai_provider_keys"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_ai_provider_keys.filters, '{}'::jsonb);
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
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'AI_KEYS_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('provider', 'enabled') then
      raise exception 'facet is one of provider, enabled' using errcode = '22023', hint = 'AI_KEYS_INVALID';
    end if;
    with s as (
      select (case v_facet when 'provider' then (x."provider")::text when 'enabled' then (x."enabled"::text)::text end) as v
      from "better_supabase"."ai_provider_keys" x
      where x."tenant_id" = page_ai_provider_keys.tenant
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."provider" ilike v_search or x."name" ilike v_search)
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
      select 1 from "better_supabase"."ai_provider_keys" x
      where x."tenant_id" = page_ai_provider_keys.tenant
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."provider" ilike v_search or x."name" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('provider', 'name', 'createdAt') then
    raise exception 'sort is one of provider, name, createdAt' using errcode = '22023', hint = 'AI_KEYS_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'AI_KEYS_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_KEYS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'provider', x."provider", 'name', x."name", 'credential_ref', x."credential_ref", 'settings', x."settings", 'enabled', x."enabled", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."provider")::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_provider_keys" x
      where x."tenant_id" = page_ai_provider_keys.tenant
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."provider" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (x."provider", lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."provider" asc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_KEYS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'provider', x."provider", 'name', x."name", 'credential_ref', x."credential_ref", 'settings', x."settings", 'enabled', x."enabled", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."provider")::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_provider_keys" x
      where x."tenant_id" = page_ai_provider_keys.tenant
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."provider" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (x."provider" <= (v_after ->> 0)::text and ((x."provider" < (v_after ->> 0)::text) or (x."provider" = (v_after ->> 0)::text and lower(x."name") > (v_after ->> 1)::text) or (x."provider" = (v_after ->> 0)::text and lower(x."name") = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."provider" desc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'provider' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_KEYS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'provider', x."provider", 'name', x."name", 'credential_ref', x."credential_ref", 'settings', x."settings", 'enabled', x."enabled", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."provider")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_provider_keys" x
      where x."tenant_id" = page_ai_provider_keys.tenant
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."provider" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (x."provider", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."provider" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'provider' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_KEYS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'provider', x."provider", 'name', x."name", 'credential_ref', x."credential_ref", 'settings', x."settings", 'enabled', x."enabled", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."provider")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_provider_keys" x
      where x."tenant_id" = page_ai_provider_keys.tenant
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."provider" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (x."provider" <= (v_after ->> 0)::text and ((x."provider" < (v_after ->> 0)::text) or (x."provider" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."provider" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_KEYS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'provider', x."provider", 'name', x."name", 'credential_ref', x."credential_ref", 'settings', x."settings", 'enabled', x."enabled", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_provider_keys" x
      where x."tenant_id" = page_ai_provider_keys.tenant
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."provider" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_KEYS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'provider', x."provider", 'name', x."name", 'credential_ref', x."credential_ref", 'settings', x."settings", 'enabled', x."enabled", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_provider_keys" x
      where x."tenant_id" = page_ai_provider_keys.tenant
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."provider" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_KEYS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'provider', x."provider", 'name', x."name", 'credential_ref', x."credential_ref", 'settings', x."settings", 'enabled', x."enabled", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_provider_keys" x
      where x."tenant_id" = page_ai_provider_keys.tenant
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."provider" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_KEYS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'provider', x."provider", 'name', x."name", 'credential_ref', x."credential_ref", 'settings', x."settings", 'enabled', x."enabled", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_provider_keys" x
      where x."tenant_id" = page_ai_provider_keys.tenant
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."provider" ilike v_search or x."name" ilike v_search)
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
      select 1 from "better_supabase"."ai_provider_keys" x
      where x."tenant_id" = page_ai_provider_keys.tenant
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."provider" ilike v_search or x."name" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_ai_provider_keys"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."page_ai_provider_keys"(uuid, jsonb) to authenticated, service_role;

-- One provider key the caller can read, or null.
create or replace function "better_supabase"."get_ai_provider_key"(id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'provider', x."provider", 'name', x."name", 'credential_ref', x."credential_ref", 'settings', x."settings", 'enabled', x."enabled", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") from "better_supabase"."ai_provider_keys" x where x."id" = get_ai_provider_key.id
$$;
revoke execute on function "better_supabase"."get_ai_provider_key"(uuid) from public, anon;
grant execute on function "better_supabase"."get_ai_provider_key"(uuid) to authenticated, service_role;

-- Adds or replaces a tenant's key for a provider ('ai_keys.manage' or the service
-- role). Returns the key and the credential_ref it replaced, which the caller
-- revokes when it differs.
create or replace function "better_supabase"."save_ai_provider_key"(tenant uuid, provider text, credential_ref jsonb, name text default 'default', settings jsonb default '{}', enabled boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_old jsonb;
  v_inserted boolean;
  v_row "better_supabase"."ai_provider_keys"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_ai_provider_key.tenant, 'ai_keys.manage'), false)) then
    raise exception 'you may not manage provider keys here' using errcode = '42501', hint = 'AI_PROVIDER_KEY_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and save_ai_provider_key.credential_ref is not null and jsonb_typeof(save_ai_provider_key.credential_ref) <> 'null'
    and (jsonb_typeof(save_ai_provider_key.credential_ref -> 'tenant') is distinct from 'string' or (save_ai_provider_key.credential_ref ->> 'tenant') is distinct from (save_ai_provider_key.tenant)::text) then
    raise exception 'credential_ref must carry the tenant % that owns it', save_ai_provider_key.tenant
      using errcode = '42501', hint = 'CREDENTIAL_REF_FOREIGN';
  end if;
  select x."credential_ref" into v_old from "better_supabase"."ai_provider_keys" x
  where x."tenant_id" = save_ai_provider_key.tenant and x."provider" = save_ai_provider_key.provider and x."name" = coalesce(save_ai_provider_key.name, 'default')
  for update;
  v_inserted := not found;
  insert into "better_supabase"."ai_provider_keys" ("tenant_id", "provider", "name", "credential_ref", "settings", "enabled", "created_by")
  values (save_ai_provider_key.tenant, save_ai_provider_key.provider, coalesce(save_ai_provider_key.name, 'default'), save_ai_provider_key.credential_ref, coalesce(save_ai_provider_key.settings, '{}'), coalesce(save_ai_provider_key.enabled, true), auth.uid())
  on conflict ("tenant_id", "provider", "name") do update set
    "credential_ref" = excluded."credential_ref",
    "settings" = excluded."settings",
    "enabled" = excluded."enabled",
    "updated_at" = now()
  returning * into v_row;
  if v_inserted then
    null;
  else
    null;
  end if;
  return jsonb_build_object('key', jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'provider', v_row."provider", 'name', v_row."name", 'credential_ref', v_row."credential_ref", 'settings', v_row."settings", 'enabled', v_row."enabled", 'created_by', v_row."created_by", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at"), 'replaced', v_old);
end;
$$;
revoke execute on function "better_supabase"."save_ai_provider_key"(uuid, text, jsonb, text, jsonb, boolean) from public, anon;
grant execute on function "better_supabase"."save_ai_provider_key"(uuid, text, jsonb, text, jsonb, boolean) to authenticated, service_role;

-- Deletes a key ('ai_keys.manage' or the service role) and returns it, so the caller
-- revokes its credential; null when there is no such key.
create or replace function "better_supabase"."delete_ai_provider_key"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."ai_provider_keys"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."ai_provider_keys" x where x."id" = delete_ai_provider_key.id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ai_keys.manage'), false)) then
    return null;
  end if;
  delete from "better_supabase"."ai_provider_keys" x where x."id" = v_row."id";
  null;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'provider', v_row."provider", 'name', v_row."name", 'credential_ref', v_row."credential_ref", 'settings', v_row."settings", 'enabled', v_row."enabled", 'created_by', v_row."created_by", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."delete_ai_provider_key"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_ai_provider_key"(uuid) to authenticated, service_role;

-- Deletes every key of a tenant and returns them (service role), for the
-- step that revokes their credentials when a tenant is deleted.
create or replace function "better_supabase"."delete_ai_provider_keys"(tenant uuid)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  with gone as (
    delete from "better_supabase"."ai_provider_keys" x where x."tenant_id" = delete_ai_provider_keys.tenant returning x.*
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', gone."id", 'tenant_id', gone."tenant_id", 'provider', gone."provider", 'name', gone."name", 'credential_ref', gone."credential_ref", 'settings', gone."settings", 'enabled', gone."enabled", 'created_by', gone."created_by", 'created_at', gone."created_at", 'updated_at', gone."updated_at")), '[]') from gone
$$;
revoke execute on function "better_supabase"."delete_ai_provider_keys"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."delete_ai_provider_keys"(uuid) to service_role;

-- The enabled keys of a tenant, for the request that resolves them (service role).
create or replace function "better_supabase"."ai_provider_keys_for"(tenant uuid, providers text[] default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'provider', x."provider", 'name', x."name", 'credential_ref', x."credential_ref", 'settings', x."settings", 'enabled', x."enabled", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") order by x."provider", x."name"), '[]')
  from "better_supabase"."ai_provider_keys" x
  where x."tenant_id" = ai_provider_keys_for.tenant and x."enabled"
    and (ai_provider_keys_for.providers is null or x."provider" = any (ai_provider_keys_for.providers))
$$;
revoke execute on function "better_supabase"."ai_provider_keys_for"(uuid, text[]) from public, anon, authenticated;
grant execute on function "better_supabase"."ai_provider_keys_for"(uuid, text[]) to service_role;

-- Records a started batch ('ai_keys.use' or the service role). fields: user_id
-- (service role only), item_count, metadata, status, raw_status, counts,
-- expires_at.
create or replace function "better_supabase"."record_ai_batch"(tenant uuid, provider text, reference jsonb, fields jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."ai_batches"%rowtype;
  v_fields jsonb := coalesce(record_ai_batch.fields, '{}');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (auth.uid() is not null and coalesce(better_supabase.can('tenant', record_ai_batch.tenant, 'ai_keys.use'), false))) then
    raise exception 'you may not start batches here' using errcode = '42501', hint = 'AI_BATCH_FORBIDDEN';
  end if;
  insert into "better_supabase"."ai_batches" ("tenant_id", "user_id", "provider", "reference", "status", "raw_status", "item_count", "counts", "metadata", "expires_at", "next_poll_at")
  values (
    record_ai_batch.tenant,
    case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (v_fields ->> 'user_id')::uuid else auth.uid() end,
    record_ai_batch.provider,
    record_ai_batch.reference,
    coalesce(v_fields ->> 'status', 'pending'),
    v_fields ->> 'raw_status',
    coalesce((v_fields ->> 'item_count')::integer, 0),
    coalesce(v_fields -> 'counts', '{}'),
    coalesce(v_fields -> 'metadata', '{}'),
    (v_fields ->> 'expires_at')::timestamptz,
    now() + interval '60 seconds'
  )
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'user_id', v_row."user_id", 'provider', v_row."provider", 'reference', v_row."reference", 'status', v_row."status", 'raw_status', v_row."raw_status", 'item_count', v_row."item_count", 'counts', v_row."counts", 'error', v_row."error", 'metadata', v_row."metadata", 'results_saved', v_row."results_saved", 'polls', v_row."polls", 'next_poll_at', v_row."next_poll_at", 'expires_at', v_row."expires_at", 'completed_at', v_row."completed_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."record_ai_batch"(uuid, text, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."record_ai_batch"(uuid, text, jsonb, jsonb) to authenticated, service_role;

-- Writes what a poll learned (service role). fields: status, raw_status,
-- counts, error, expires_at, results_saved, next_poll_at.
create or replace function "better_supabase"."update_ai_batch"(id uuid, fields jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."ai_batches"%rowtype;
  v_fields jsonb := coalesce(update_ai_batch.fields, '{}');
begin
  update "better_supabase"."ai_batches" x set
    "status" = coalesce(v_fields ->> 'status', x."status"),
    "raw_status" = coalesce(v_fields ->> 'raw_status', x."raw_status"),
    "counts" = coalesce(v_fields -> 'counts', x."counts"),
    "error" = case when v_fields ? 'error' then left(v_fields ->> 'error', 4000) else x."error" end,
    "expires_at" = coalesce((v_fields ->> 'expires_at')::timestamptz, x."expires_at"),
    "results_saved" = coalesce((v_fields ->> 'results_saved')::boolean, x."results_saved"),
    "next_poll_at" = case when v_fields ? 'next_poll_at' then (v_fields ->> 'next_poll_at')::timestamptz else x."next_poll_at" end,
    "completed_at" = case when coalesce(v_fields ->> 'status', x."status") <> 'pending' then coalesce(x."completed_at", now()) else null end,
    "updated_at" = now()
  where x."id" = update_ai_batch.id
  returning * into v_row;
  if not found then
    raise exception 'batch % not found', update_ai_batch.id using errcode = 'P0002', hint = 'AI_BATCH_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'user_id', v_row."user_id", 'provider', v_row."provider", 'reference', v_row."reference", 'status', v_row."status", 'raw_status', v_row."raw_status", 'item_count', v_row."item_count", 'counts', v_row."counts", 'error', v_row."error", 'metadata', v_row."metadata", 'results_saved', v_row."results_saved", 'polls', v_row."polls", 'next_poll_at', v_row."next_poll_at", 'expires_at', v_row."expires_at", 'completed_at', v_row."completed_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_ai_batch"(uuid, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."update_ai_batch"(uuid, jsonb) to service_role;

-- Claims batches to poll (service role): pending ones, and finished ones
-- whose results aren't saved yet. Each claim pushes next_poll_at out by
-- lease_seconds, so two pollers don't take the same batch.
create or replace function "better_supabase"."due_ai_batches"(batch integer default 20, lease_seconds integer default 300)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rows jsonb;
begin
  with due as (
    select y."id" from "better_supabase"."ai_batches" y
    where (y."status" = 'pending' or not y."results_saved") and y."next_poll_at" <= now()
    order by y."next_poll_at"
    limit least(greatest(due_ai_batches.batch, 1), 200)
    for update skip locked
  ), claimed as (
    update "better_supabase"."ai_batches" x set
      "polls" = x."polls" + 1,
      "next_poll_at" = now() + make_interval(secs => greatest(due_ai_batches.lease_seconds, 1)),
      "updated_at" = now()
    from due where x."id" = due."id"
    returning x.*
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', claimed."id", 'tenant_id', claimed."tenant_id", 'user_id', claimed."user_id", 'provider', claimed."provider", 'reference', claimed."reference", 'status', claimed."status", 'raw_status', claimed."raw_status", 'item_count', claimed."item_count", 'counts', claimed."counts", 'error', claimed."error", 'metadata', claimed."metadata", 'results_saved', claimed."results_saved", 'polls', claimed."polls", 'next_poll_at', claimed."next_poll_at", 'expires_at', claimed."expires_at", 'completed_at', claimed."completed_at", 'created_at', claimed."created_at", 'updated_at', claimed."updated_at")), '[]') into v_rows from claimed;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."due_ai_batches"(integer, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."due_ai_batches"(integer, integer) to service_role;

-- Saves result items: { "items": [{ "request_id", "status", "output",
-- "usage", "error" }] } (service role). Returns how many were written.
create or replace function "better_supabase"."save_ai_batch_items"(id uuid, items jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_items jsonb := case when jsonb_typeof(save_ai_batch_items.items) = 'object' then save_ai_batch_items.items -> 'items' else save_ai_batch_items.items end;
  v_count integer;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."ai_batches" x where x."id" = save_ai_batch_items.id;
  if not found then
    raise exception 'batch % not found', save_ai_batch_items.id using errcode = 'P0002', hint = 'AI_BATCH_NOT_FOUND';
  end if;
  insert into "better_supabase"."ai_batch_items" ("batch_id", "request_id", "tenant_id", "status", "output", "usage", "error")
  select save_ai_batch_items.id, item ->> 'request_id', v_tenant, item ->> 'status', item -> 'output', item -> 'usage', left(item ->> 'error', 4000)
  from jsonb_array_elements(case when jsonb_typeof(v_items) = 'array' then v_items else '[]' end) item
  on conflict ("batch_id", "request_id") do update set
    "status" = excluded."status",
    "output" = excluded."output",
    "usage" = excluded."usage",
    "error" = excluded."error";
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."save_ai_batch_items"(uuid, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."save_ai_batch_items"(uuid, jsonb) to service_role;

create or replace function "better_supabase"."get_ai_batch"(id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'user_id', x."user_id", 'provider', x."provider", 'reference', x."reference", 'status', x."status", 'raw_status', x."raw_status", 'item_count', x."item_count", 'counts', x."counts", 'error', x."error", 'metadata', x."metadata", 'results_saved', x."results_saved", 'polls', x."polls", 'next_poll_at', x."next_poll_at", 'expires_at', x."expires_at", 'completed_at', x."completed_at", 'created_at', x."created_at", 'updated_at', x."updated_at") from "better_supabase"."ai_batches" x where x."id" = get_ai_batch.id
$$;
revoke execute on function "better_supabase"."get_ai_batch"(uuid) from public, anon;
grant execute on function "better_supabase"."get_ai_batch"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_ai_batches"(tenant uuid, status text default null, max_rows integer default 50)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'user_id', x."user_id", 'provider', x."provider", 'reference', x."reference", 'status', x."status", 'raw_status', x."raw_status", 'item_count', x."item_count", 'counts', x."counts", 'error', x."error", 'metadata', x."metadata", 'results_saved', x."results_saved", 'polls', x."polls", 'next_poll_at', x."next_poll_at", 'expires_at', x."expires_at", 'completed_at', x."completed_at", 'created_at', x."created_at", 'updated_at', x."updated_at") order by x."created_at" desc), '[]')
  from (
    select * from "better_supabase"."ai_batches" y
    where y."tenant_id" = list_ai_batches.tenant and (list_ai_batches.status is null or y."status" = list_ai_batches.status)
    order by y."created_at" desc
    limit least(greatest(list_ai_batches.max_rows, 1), 200)
  ) x
$$;
revoke execute on function "better_supabase"."list_ai_batches"(uuid, text, integer) from public, anon;
grant execute on function "better_supabase"."list_ai_batches"(uuid, text, integer) to authenticated, service_role;

-- The tenant's batches as a keyset page (ADR 1077), newest first. filters is
-- { status, provider (a value or a list), sort (createdAt, provider, status),
-- direction, facet, count, limit, after, offset, paged, total, totalCap }.
-- Batches have no text, so there is no search.
create or replace function "better_supabase"."page_ai_batches"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_ai_batches.filters, '{}'::jsonb);
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
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'AI_BATCH_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'provider') then
      raise exception 'facet is one of status, provider' using errcode = '22023', hint = 'AI_BATCH_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'provider' then (x."provider")::text end) as v
      from "better_supabase"."ai_batches" x
      where x."tenant_id" = page_ai_batches.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
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
      select 1 from "better_supabase"."ai_batches" x
      where x."tenant_id" = page_ai_batches.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'provider', 'status') then
    raise exception 'sort is one of createdAt, provider, status' using errcode = '22023', hint = 'AI_BATCH_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'AI_BATCH_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_BATCH_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'user_id', x."user_id", 'provider', x."provider", 'reference', x."reference", 'status', x."status", 'raw_status', x."raw_status", 'item_count', x."item_count", 'counts', x."counts", 'error', x."error", 'metadata', x."metadata", 'results_saved', x."results_saved", 'polls', x."polls", 'next_poll_at', x."next_poll_at", 'expires_at', x."expires_at", 'completed_at', x."completed_at", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_batches" x
      where x."tenant_id" = page_ai_batches.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_BATCH_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'user_id', x."user_id", 'provider', x."provider", 'reference', x."reference", 'status', x."status", 'raw_status', x."raw_status", 'item_count', x."item_count", 'counts', x."counts", 'error', x."error", 'metadata', x."metadata", 'results_saved', x."results_saved", 'polls', x."polls", 'next_poll_at', x."next_poll_at", 'expires_at', x."expires_at", 'completed_at', x."completed_at", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_batches" x
      where x."tenant_id" = page_ai_batches.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_BATCH_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'user_id', x."user_id", 'provider', x."provider", 'reference', x."reference", 'status', x."status", 'raw_status', x."raw_status", 'item_count', x."item_count", 'counts', x."counts", 'error', x."error", 'metadata', x."metadata", 'results_saved', x."results_saved", 'polls', x."polls", 'next_poll_at', x."next_poll_at", 'expires_at', x."expires_at", 'completed_at', x."completed_at", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_batches" x
      where x."tenant_id" = page_ai_batches.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_BATCH_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'user_id', x."user_id", 'provider', x."provider", 'reference', x."reference", 'status', x."status", 'raw_status', x."raw_status", 'item_count', x."item_count", 'counts', x."counts", 'error', x."error", 'metadata', x."metadata", 'results_saved', x."results_saved", 'polls', x."polls", 'next_poll_at', x."next_poll_at", 'expires_at', x."expires_at", 'completed_at', x."completed_at", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_batches" x
      where x."tenant_id" = page_ai_batches.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'provider' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_BATCH_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'user_id', x."user_id", 'provider', x."provider", 'reference', x."reference", 'status', x."status", 'raw_status', x."raw_status", 'item_count', x."item_count", 'counts', x."counts", 'error', x."error", 'metadata', x."metadata", 'results_saved', x."results_saved", 'polls', x."polls", 'next_poll_at', x."next_poll_at", 'expires_at', x."expires_at", 'completed_at', x."completed_at", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."provider")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_batches" x
      where x."tenant_id" = page_ai_batches.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (v_after is null or (x."provider", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."provider" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'provider' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_BATCH_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'user_id', x."user_id", 'provider', x."provider", 'reference', x."reference", 'status', x."status", 'raw_status', x."raw_status", 'item_count', x."item_count", 'counts', x."counts", 'error', x."error", 'metadata', x."metadata", 'results_saved', x."results_saved", 'polls', x."polls", 'next_poll_at', x."next_poll_at", 'expires_at', x."expires_at", 'completed_at', x."completed_at", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."provider")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_batches" x
      where x."tenant_id" = page_ai_batches.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (v_after is null or (x."provider" <= (v_after ->> 0)::text and ((x."provider" < (v_after ->> 0)::text) or (x."provider" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."provider" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'status' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_BATCH_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'user_id', x."user_id", 'provider', x."provider", 'reference', x."reference", 'status', x."status", 'raw_status', x."raw_status", 'item_count', x."item_count", 'counts', x."counts", 'error', x."error", 'metadata', x."metadata", 'results_saved', x."results_saved", 'polls', x."polls", 'next_poll_at', x."next_poll_at", 'expires_at', x."expires_at", 'completed_at', x."completed_at", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."status")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_batches" x
      where x."tenant_id" = page_ai_batches.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (v_after is null or (x."status", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."status" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'status' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_BATCH_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'user_id', x."user_id", 'provider', x."provider", 'reference', x."reference", 'status', x."status", 'raw_status', x."raw_status", 'item_count', x."item_count", 'counts', x."counts", 'error', x."error", 'metadata', x."metadata", 'results_saved', x."results_saved", 'polls', x."polls", 'next_poll_at', x."next_poll_at", 'expires_at', x."expires_at", 'completed_at', x."completed_at", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."status")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_batches" x
      where x."tenant_id" = page_ai_batches.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (v_after is null or (x."status" <= (v_after ->> 0)::text and ((x."status" < (v_after ->> 0)::text) or (x."status" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."status" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."ai_batches" x
      where x."tenant_id" = page_ai_batches.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_ai_batches"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."page_ai_batches"(uuid, jsonb) to authenticated, service_role;

-- A page of a batch's results, after request_id after.
create or replace function "better_supabase"."list_ai_batch_items"(id uuid, after text default null, max_rows integer default 100)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('batch_id', x."batch_id", 'request_id', x."request_id", 'tenant_id', x."tenant_id", 'status', x."status", 'output', x."output", 'usage', x."usage", 'error', x."error", 'created_at', x."created_at") order by x."request_id"), '[]')
  from (
    select * from "better_supabase"."ai_batch_items" y
    where y."batch_id" = list_ai_batch_items.id and (list_ai_batch_items.after is null or y."request_id" > list_ai_batch_items.after)
    order by y."request_id"
    limit least(greatest(list_ai_batch_items.max_rows, 1), 1000)
  ) x
$$;
revoke execute on function "better_supabase"."list_ai_batch_items"(uuid, text, integer) from public, anon;
grant execute on function "better_supabase"."list_ai_batch_items"(uuid, text, integer) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."ai_provider_keys" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('ai_keys.manage')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."ai_provider_keys" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."ai_provider_keys" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."ai_provider_keys" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."ai_batches" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('ai_keys.manage')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."ai_batches" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."ai_batches" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."ai_batches" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."ai_batch_items" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or (exists (select 1 from "better_supabase"."ai_batches" y where y."id" = "batch_id"))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."ai_batch_items" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."ai_batch_items" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."ai_batch_items" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));

-- ==== data supabase/better-supabase-data/900_better_supabase_056_ai_keys.sql
-- better-supabase module: ai-keys
-- @bsb-block-data ai-keys
-- @bsb-hash sha256:59f49d5cd582b88f958553f7215a99189f65f822edc9f26c08913b28d7fe4b72
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('ai-keys', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
