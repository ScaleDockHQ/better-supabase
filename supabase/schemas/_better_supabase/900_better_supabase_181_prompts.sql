-- better-supabase module: prompts
-- @bsb-block prompts@1 managed
-- @bsb-hash sha256:a2a8d740759f36183a089b189c3a0476018ff286d1eb1ff9fd526cff366c88dc
-- Versioned prompt templates by name, per tenant or for the whole system, with labels such as production that point at one version; only the service role reads and writes them.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Prompt templates the application versions by name, per tenant or for the
-- whole system (tenant is null). A version never changes once saved; a label
-- such as production points at one version. Templates can hold instructions
-- and secrets, so only the service role reads and writes them.
create table "better_supabase"."prompt_versions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid,
  "name" text not null constraint bsb_prompt_versions_name_check check ("name" ~ '^[a-z0-9][a-z0-9_.:/-]{0,127}$'),
  "version" integer not null constraint bsb_prompt_versions_version_check check ("version" >= 1),
  "template" text not null constraint bsb_prompt_versions_template_check check (length("template") >= 1 and length("template") <= 102400),
  "variables" jsonb not null default '[]'::jsonb constraint bsb_prompt_versions_variables_check check (jsonb_typeof("variables") = 'array'),
  "created_at" timestamptz not null default now()
);
create unique index "bsb_prompt_versions_key" on "better_supabase"."prompt_versions" ((coalesce("tenant_id"::text, '')), "name", "version");
create index "prompt_versions_tenant_idx" on "better_supabase"."prompt_versions" ("tenant_id");
alter table "better_supabase"."prompt_versions" enable row level security;
revoke all on "better_supabase"."prompt_versions" from public, anon, authenticated;
grant all on "better_supabase"."prompt_versions" to service_role;

create table "better_supabase"."prompt_labels" (
  "tenant_id" uuid,
  "name" text not null,
  "label" text not null constraint bsb_prompt_labels_label_check check ("label" ~ '^[a-z0-9][a-z0-9_-]{0,63}$'),
  "version" integer not null constraint bsb_prompt_labels_version_check check ("version" >= 1),
  "updated_at" timestamptz not null default now()
);
create unique index "bsb_prompt_labels_key" on "better_supabase"."prompt_labels" ((coalesce("tenant_id"::text, '')), "name", "label");
create index "prompt_labels_tenant_idx" on "better_supabase"."prompt_labels" ("tenant_id");
alter table "better_supabase"."prompt_labels" enable row level security;
revoke all on "better_supabase"."prompt_labels" from public, anon, authenticated;
grant all on "better_supabase"."prompt_labels" to service_role;

-- Creates template as the next version of name and returns it. A label moves to
-- the new version in the same call.
create or replace function "better_supabase"."create_prompt_version"(name text, template text, tenant uuid default null, variables jsonb default '[]'::jsonb, label text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."prompt_versions"%rowtype;
  v_next integer;
begin
  perform pg_advisory_xact_lock(hashtextextended(coalesce(create_prompt_version.tenant::text, '') || ':' || create_prompt_version.name, 0));
  select coalesce(max(x."version"), 0) + 1 into v_next from "better_supabase"."prompt_versions" x
  where coalesce(x."tenant_id"::text, '') = coalesce(create_prompt_version.tenant::text, '') and x."name" = create_prompt_version.name;
  insert into "better_supabase"."prompt_versions" ("tenant_id", "name", "version", "template", "variables")
  values (create_prompt_version.tenant, create_prompt_version.name, v_next, create_prompt_version.template, coalesce(create_prompt_version.variables, '[]'::jsonb))
  returning * into v_row;
  if create_prompt_version.label is not null then
    insert into "better_supabase"."prompt_labels" ("tenant_id", "name", "label", "version")
    values (create_prompt_version.tenant, create_prompt_version.name, create_prompt_version.label, v_next)
    on conflict ((coalesce("tenant_id"::text, '')), "name", "label") do update set
      "version" = excluded."version",
      "updated_at" = now();
  end if;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'name', v_row."name", 'version', v_row."version", 'template', v_row."template", 'variables', v_row."variables", 'created_at', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."create_prompt_version"(text, text, uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."create_prompt_version"(text, text, uuid, jsonb, text) to service_role;

-- The version of name that label (default production) points at, or the
-- exact version when one is given. A tenant's own prompt wins over the
-- system prompt of the same name. Null when there is none.
create or replace function "better_supabase"."get_prompt"(name text, label text default 'production', version integer default null, tenant uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."prompt_versions"%rowtype;
begin
  select x.* into v_row from "better_supabase"."prompt_versions" x
  where x."name" = get_prompt.name
    and (x."tenant_id" is null or x."tenant_id" = get_prompt.tenant)
    and (
      (get_prompt.version is not null and x."version" = get_prompt.version)
      or (get_prompt.version is null and exists (
        select 1 from "better_supabase"."prompt_labels" y
        where coalesce(y."tenant_id"::text, '') = coalesce(x."tenant_id"::text, '')
          and y."name" = x."name"
          and y."label" = get_prompt.label
          and y."version" = x."version"
      ))
    )
  order by (x."tenant_id" is null), x."version" desc
  limit 1;
  if not found then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'name', v_row."name", 'version', v_row."version", 'template', v_row."template", 'variables', v_row."variables", 'created_at', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."get_prompt"(text, text, integer, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."get_prompt"(text, text, integer, uuid) to service_role;

-- Points label at an existing version of name and returns the version.
create or replace function "better_supabase"."set_prompt_label"(name text, label text, version integer, tenant uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."prompt_versions"%rowtype;
begin
  select x.* into v_row from "better_supabase"."prompt_versions" x
  where x."name" = set_prompt_label.name
    and x."version" = set_prompt_label.version
    and coalesce(x."tenant_id"::text, '') = coalesce(set_prompt_label.tenant::text, '');
  if not found then
    raise exception 'No version % of prompt %', set_prompt_label.version, set_prompt_label.name using errcode = 'P0002', hint = 'PROMPT_NOT_FOUND';
  end if;
  insert into "better_supabase"."prompt_labels" ("tenant_id", "name", "label", "version")
  values (set_prompt_label.tenant, set_prompt_label.name, set_prompt_label.label, set_prompt_label.version)
  on conflict ((coalesce("tenant_id"::text, '')), "name", "label") do update set
    "version" = excluded."version",
    "updated_at" = now();
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'name', v_row."name", 'version', v_row."version", 'template', v_row."template", 'variables', v_row."variables", 'created_at', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."set_prompt_label"(text, text, integer, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."set_prompt_label"(text, text, integer, uuid) to service_role;

-- Every version of name for a tenant (or the system when tenant is null),
-- newest first, each with the labels that point at it.
create or replace function "better_supabase"."list_prompt_versions"(name text, tenant uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'name', x."name", 'version', x."version", 'template', x."template", 'variables', x."variables", 'created_at', x."created_at") || jsonb_build_object('labels', coalesce((
      select jsonb_agg(y."label" order by y."label") from "better_supabase"."prompt_labels" y
      where coalesce(y."tenant_id"::text, '') = coalesce(x."tenant_id"::text, '')
        and y."name" = x."name" and y."version" = x."version"
    ), '[]'::jsonb)) order by x."version" desc), '[]'::jsonb)
    from "better_supabase"."prompt_versions" x
    where x."name" = list_prompt_versions.name
      and coalesce(x."tenant_id"::text, '') = coalesce(list_prompt_versions.tenant::text, '')
  );
end;
$$;
revoke execute on function "better_supabase"."list_prompt_versions"(text, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."list_prompt_versions"(text, uuid) to service_role;

-- One page of the prompt names a tenant (or the system when tenant is null)
-- has saved, in name order. Each item has the latest version, how many
-- versions exist, the labels with the version each points at, and when the
-- latest version was saved. after is the last name of the previous page. It
-- runs as invoker: only the service role may call it and it reads no template.
create or replace function "better_supabase"."list_prompts"(tenant uuid default null, after text default null, max_rows integer default 50)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_size integer := least(greatest(coalesce(list_prompts.max_rows, 50), 1), 200);
  v_items jsonb;
  v_more boolean;
begin
  select coalesce(jsonb_agg(n.item order by n.name), '[]'::jsonb) into v_items
  from (
    select x."name" as name, jsonb_build_object(
      'name', x."name",
      'tenant_id', list_prompts.tenant,
      'latest_version', max(x."version"),
      'version_count', count(*),
      'updated_at', max(x."created_at"),
      'labels', coalesce((
        select jsonb_object_agg(y."label", y."version") from "better_supabase"."prompt_labels" y
        where coalesce(y."tenant_id"::text, '') = coalesce(list_prompts.tenant::text, '') and y."name" = x."name"
      ), '{}'::jsonb)
    ) as item
    from "better_supabase"."prompt_versions" x
    where coalesce(x."tenant_id"::text, '') = coalesce(list_prompts.tenant::text, '')
      and (list_prompts.after is null or x."name" > list_prompts.after)
    group by x."name"
    order by x."name"
    limit v_size + 1
  ) n;
  v_more := jsonb_array_length(v_items) > v_size;
  if v_more then
    v_items := v_items - v_size;
  end if;
  return jsonb_build_object(
    'items', v_items,
    'hasMore', v_more,
    'nextCursor', case when v_more then jsonb_build_array(v_items -> (v_size - 1) ->> 'name') else null end
  );
end;
$$;
revoke execute on function "better_supabase"."list_prompts"(uuid, text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."list_prompts"(uuid, text, integer) to service_role;

-- The prompt names of a tenant (the system when tenant is null) as a keyset
-- page (ADR 1077), with the same items as list_prompts. filters is { name,
-- label (each a value or a list), search (name), sort (name, updatedAt,
-- versionCount), direction, count, limit, after, offset, paged, total,
-- totalCap }. Service role only, and it reads no template.
create or replace function "better_supabase"."page_prompts"(tenant uuid default null, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_prompts.filters, '{}'::jsonb);
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
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'PROMPT_INVALID';
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from (
    select g."name" as name,
      max(g."version") as latest_version,
      count(*) as version_count,
      max(g."created_at") as updated_at,
      coalesce((
        select jsonb_object_agg(y."label", y."version") from "better_supabase"."prompt_labels" y
        where coalesce(y."tenant_id"::text, '') = coalesce(page_prompts.tenant::text, '') and y."name" = g."name"
      ), '{}'::jsonb) as labels
    from "better_supabase"."prompt_versions" g
    where coalesce(g."tenant_id"::text, '') = coalesce(page_prompts.tenant::text, '')
    group by g."name"
  ) x
      where (not (v_filters -> 'name' is not null and jsonb_typeof(v_filters -> 'name') <> 'null' and not (jsonb_typeof(v_filters -> 'name') = 'array' and jsonb_array_length(v_filters -> 'name') = 0)) or (x.name)::text = any((case when jsonb_typeof(v_filters -> 'name') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'name')) else array[v_filters ->> 'name'] end)::text[]))
        and (not (v_filters -> 'label' is not null and jsonb_typeof(v_filters -> 'label') <> 'null' and not (jsonb_typeof(v_filters -> 'label') = 'array' and jsonb_array_length(v_filters -> 'label') = 0)) or x.labels ?| (case when jsonb_typeof(v_filters -> 'label') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'label')) else array[v_filters ->> 'label'] end))
        and (v_search is null or x.name ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'updatedAt', 'versionCount') then
    raise exception 'sort is one of name, updatedAt, versionCount' using errcode = '22023', hint = 'PROMPT_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'PROMPT_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 1) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PROMPT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('name', x.name, 'tenant_id', page_prompts.tenant, 'latest_version', x.latest_version, 'version_count', x.version_count, 'updated_at', x.updated_at, 'labels', x.labels) as j, jsonb_build_array((x.name)::text) as k
    from (
      select * from (
    select g."name" as name,
      max(g."version") as latest_version,
      count(*) as version_count,
      max(g."created_at") as updated_at,
      coalesce((
        select jsonb_object_agg(y."label", y."version") from "better_supabase"."prompt_labels" y
        where coalesce(y."tenant_id"::text, '') = coalesce(page_prompts.tenant::text, '') and y."name" = g."name"
      ), '{}'::jsonb) as labels
    from "better_supabase"."prompt_versions" g
    where coalesce(g."tenant_id"::text, '') = coalesce(page_prompts.tenant::text, '')
    group by g."name"
  ) x
      where (not (v_filters -> 'name' is not null and jsonb_typeof(v_filters -> 'name') <> 'null' and not (jsonb_typeof(v_filters -> 'name') = 'array' and jsonb_array_length(v_filters -> 'name') = 0)) or (x.name)::text = any((case when jsonb_typeof(v_filters -> 'name') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'name')) else array[v_filters ->> 'name'] end)::text[]))
        and (not (v_filters -> 'label' is not null and jsonb_typeof(v_filters -> 'label') <> 'null' and not (jsonb_typeof(v_filters -> 'label') = 'array' and jsonb_array_length(v_filters -> 'label') = 0)) or x.labels ?| (case when jsonb_typeof(v_filters -> 'label') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'label')) else array[v_filters ->> 'label'] end))
        and (v_search is null or x.name ilike v_search)
        and (v_after is null or (x.name) > ((v_after ->> 0)::text))
      order by x.name asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 1) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PROMPT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('name', x.name, 'tenant_id', page_prompts.tenant, 'latest_version', x.latest_version, 'version_count', x.version_count, 'updated_at', x.updated_at, 'labels', x.labels) as j, jsonb_build_array((x.name)::text) as k
    from (
      select * from (
    select g."name" as name,
      max(g."version") as latest_version,
      count(*) as version_count,
      max(g."created_at") as updated_at,
      coalesce((
        select jsonb_object_agg(y."label", y."version") from "better_supabase"."prompt_labels" y
        where coalesce(y."tenant_id"::text, '') = coalesce(page_prompts.tenant::text, '') and y."name" = g."name"
      ), '{}'::jsonb) as labels
    from "better_supabase"."prompt_versions" g
    where coalesce(g."tenant_id"::text, '') = coalesce(page_prompts.tenant::text, '')
    group by g."name"
  ) x
      where (not (v_filters -> 'name' is not null and jsonb_typeof(v_filters -> 'name') <> 'null' and not (jsonb_typeof(v_filters -> 'name') = 'array' and jsonb_array_length(v_filters -> 'name') = 0)) or (x.name)::text = any((case when jsonb_typeof(v_filters -> 'name') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'name')) else array[v_filters ->> 'name'] end)::text[]))
        and (not (v_filters -> 'label' is not null and jsonb_typeof(v_filters -> 'label') <> 'null' and not (jsonb_typeof(v_filters -> 'label') = 'array' and jsonb_array_length(v_filters -> 'label') = 0)) or x.labels ?| (case when jsonb_typeof(v_filters -> 'label') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'label')) else array[v_filters ->> 'label'] end))
        and (v_search is null or x.name ilike v_search)
        and (v_after is null or (x.name) < ((v_after ->> 0)::text))
      order by x.name desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 1) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PROMPT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('name', x.name, 'tenant_id', page_prompts.tenant, 'latest_version', x.latest_version, 'version_count', x.version_count, 'updated_at', x.updated_at, 'labels', x.labels) as j, jsonb_build_array((x.name)::text) as k
    from (
      select * from (
    select g."name" as name,
      max(g."version") as latest_version,
      count(*) as version_count,
      max(g."created_at") as updated_at,
      coalesce((
        select jsonb_object_agg(y."label", y."version") from "better_supabase"."prompt_labels" y
        where coalesce(y."tenant_id"::text, '') = coalesce(page_prompts.tenant::text, '') and y."name" = g."name"
      ), '{}'::jsonb) as labels
    from "better_supabase"."prompt_versions" g
    where coalesce(g."tenant_id"::text, '') = coalesce(page_prompts.tenant::text, '')
    group by g."name"
  ) x
      where (not (v_filters -> 'name' is not null and jsonb_typeof(v_filters -> 'name') <> 'null' and not (jsonb_typeof(v_filters -> 'name') = 'array' and jsonb_array_length(v_filters -> 'name') = 0)) or (x.name)::text = any((case when jsonb_typeof(v_filters -> 'name') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'name')) else array[v_filters ->> 'name'] end)::text[]))
        and (not (v_filters -> 'label' is not null and jsonb_typeof(v_filters -> 'label') <> 'null' and not (jsonb_typeof(v_filters -> 'label') = 'array' and jsonb_array_length(v_filters -> 'label') = 0)) or x.labels ?| (case when jsonb_typeof(v_filters -> 'label') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'label')) else array[v_filters ->> 'label'] end))
        and (v_search is null or x.name ilike v_search)
        and (v_after is null or (x.name) > ((v_after ->> 0)::text))
      order by x.name asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 1) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PROMPT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('name', x.name, 'tenant_id', page_prompts.tenant, 'latest_version', x.latest_version, 'version_count', x.version_count, 'updated_at', x.updated_at, 'labels', x.labels) as j, jsonb_build_array((x.name)::text) as k
    from (
      select * from (
    select g."name" as name,
      max(g."version") as latest_version,
      count(*) as version_count,
      max(g."created_at") as updated_at,
      coalesce((
        select jsonb_object_agg(y."label", y."version") from "better_supabase"."prompt_labels" y
        where coalesce(y."tenant_id"::text, '') = coalesce(page_prompts.tenant::text, '') and y."name" = g."name"
      ), '{}'::jsonb) as labels
    from "better_supabase"."prompt_versions" g
    where coalesce(g."tenant_id"::text, '') = coalesce(page_prompts.tenant::text, '')
    group by g."name"
  ) x
      where (not (v_filters -> 'name' is not null and jsonb_typeof(v_filters -> 'name') <> 'null' and not (jsonb_typeof(v_filters -> 'name') = 'array' and jsonb_array_length(v_filters -> 'name') = 0)) or (x.name)::text = any((case when jsonb_typeof(v_filters -> 'name') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'name')) else array[v_filters ->> 'name'] end)::text[]))
        and (not (v_filters -> 'label' is not null and jsonb_typeof(v_filters -> 'label') <> 'null' and not (jsonb_typeof(v_filters -> 'label') = 'array' and jsonb_array_length(v_filters -> 'label') = 0)) or x.labels ?| (case when jsonb_typeof(v_filters -> 'label') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'label')) else array[v_filters ->> 'label'] end))
        and (v_search is null or x.name ilike v_search)
        and (v_after is null or (x.name) < ((v_after ->> 0)::text))
      order by x.name desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PROMPT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('name', x.name, 'tenant_id', page_prompts.tenant, 'latest_version', x.latest_version, 'version_count', x.version_count, 'updated_at', x.updated_at, 'labels', x.labels) as j, jsonb_build_array((coalesce(x.updated_at, 'epoch'::timestamptz))::text, (x.name)::text) as k
    from (
      select * from (
    select g."name" as name,
      max(g."version") as latest_version,
      count(*) as version_count,
      max(g."created_at") as updated_at,
      coalesce((
        select jsonb_object_agg(y."label", y."version") from "better_supabase"."prompt_labels" y
        where coalesce(y."tenant_id"::text, '') = coalesce(page_prompts.tenant::text, '') and y."name" = g."name"
      ), '{}'::jsonb) as labels
    from "better_supabase"."prompt_versions" g
    where coalesce(g."tenant_id"::text, '') = coalesce(page_prompts.tenant::text, '')
    group by g."name"
  ) x
      where (not (v_filters -> 'name' is not null and jsonb_typeof(v_filters -> 'name') <> 'null' and not (jsonb_typeof(v_filters -> 'name') = 'array' and jsonb_array_length(v_filters -> 'name') = 0)) or (x.name)::text = any((case when jsonb_typeof(v_filters -> 'name') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'name')) else array[v_filters ->> 'name'] end)::text[]))
        and (not (v_filters -> 'label' is not null and jsonb_typeof(v_filters -> 'label') <> 'null' and not (jsonb_typeof(v_filters -> 'label') = 'array' and jsonb_array_length(v_filters -> 'label') = 0)) or x.labels ?| (case when jsonb_typeof(v_filters -> 'label') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'label')) else array[v_filters ->> 'label'] end))
        and (v_search is null or x.name ilike v_search)
        and (v_after is null or (coalesce(x.updated_at, 'epoch'::timestamptz), x.name) > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::text))
      order by coalesce(x.updated_at, 'epoch'::timestamptz) asc, x.name asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PROMPT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('name', x.name, 'tenant_id', page_prompts.tenant, 'latest_version', x.latest_version, 'version_count', x.version_count, 'updated_at', x.updated_at, 'labels', x.labels) as j, jsonb_build_array((coalesce(x.updated_at, 'epoch'::timestamptz))::text, (x.name)::text) as k
    from (
      select * from (
    select g."name" as name,
      max(g."version") as latest_version,
      count(*) as version_count,
      max(g."created_at") as updated_at,
      coalesce((
        select jsonb_object_agg(y."label", y."version") from "better_supabase"."prompt_labels" y
        where coalesce(y."tenant_id"::text, '') = coalesce(page_prompts.tenant::text, '') and y."name" = g."name"
      ), '{}'::jsonb) as labels
    from "better_supabase"."prompt_versions" g
    where coalesce(g."tenant_id"::text, '') = coalesce(page_prompts.tenant::text, '')
    group by g."name"
  ) x
      where (not (v_filters -> 'name' is not null and jsonb_typeof(v_filters -> 'name') <> 'null' and not (jsonb_typeof(v_filters -> 'name') = 'array' and jsonb_array_length(v_filters -> 'name') = 0)) or (x.name)::text = any((case when jsonb_typeof(v_filters -> 'name') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'name')) else array[v_filters ->> 'name'] end)::text[]))
        and (not (v_filters -> 'label' is not null and jsonb_typeof(v_filters -> 'label') <> 'null' and not (jsonb_typeof(v_filters -> 'label') = 'array' and jsonb_array_length(v_filters -> 'label') = 0)) or x.labels ?| (case when jsonb_typeof(v_filters -> 'label') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'label')) else array[v_filters ->> 'label'] end))
        and (v_search is null or x.name ilike v_search)
        and (v_after is null or (coalesce(x.updated_at, 'epoch'::timestamptz) <= (v_after ->> 0)::timestamptz and ((coalesce(x.updated_at, 'epoch'::timestamptz) < (v_after ->> 0)::timestamptz) or (coalesce(x.updated_at, 'epoch'::timestamptz) = (v_after ->> 0)::timestamptz and x.name > (v_after ->> 1)::text))))
      order by coalesce(x.updated_at, 'epoch'::timestamptz) desc, x.name asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'versionCount' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PROMPT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('name', x.name, 'tenant_id', page_prompts.tenant, 'latest_version', x.latest_version, 'version_count', x.version_count, 'updated_at', x.updated_at, 'labels', x.labels) as j, jsonb_build_array((x.version_count)::text, (x.name)::text) as k
    from (
      select * from (
    select g."name" as name,
      max(g."version") as latest_version,
      count(*) as version_count,
      max(g."created_at") as updated_at,
      coalesce((
        select jsonb_object_agg(y."label", y."version") from "better_supabase"."prompt_labels" y
        where coalesce(y."tenant_id"::text, '') = coalesce(page_prompts.tenant::text, '') and y."name" = g."name"
      ), '{}'::jsonb) as labels
    from "better_supabase"."prompt_versions" g
    where coalesce(g."tenant_id"::text, '') = coalesce(page_prompts.tenant::text, '')
    group by g."name"
  ) x
      where (not (v_filters -> 'name' is not null and jsonb_typeof(v_filters -> 'name') <> 'null' and not (jsonb_typeof(v_filters -> 'name') = 'array' and jsonb_array_length(v_filters -> 'name') = 0)) or (x.name)::text = any((case when jsonb_typeof(v_filters -> 'name') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'name')) else array[v_filters ->> 'name'] end)::text[]))
        and (not (v_filters -> 'label' is not null and jsonb_typeof(v_filters -> 'label') <> 'null' and not (jsonb_typeof(v_filters -> 'label') = 'array' and jsonb_array_length(v_filters -> 'label') = 0)) or x.labels ?| (case when jsonb_typeof(v_filters -> 'label') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'label')) else array[v_filters ->> 'label'] end))
        and (v_search is null or x.name ilike v_search)
        and (v_after is null or (x.version_count, x.name) > ((v_after ->> 0)::bigint, (v_after ->> 1)::text))
      order by x.version_count asc, x.name asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'versionCount' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PROMPT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('name', x.name, 'tenant_id', page_prompts.tenant, 'latest_version', x.latest_version, 'version_count', x.version_count, 'updated_at', x.updated_at, 'labels', x.labels) as j, jsonb_build_array((x.version_count)::text, (x.name)::text) as k
    from (
      select * from (
    select g."name" as name,
      max(g."version") as latest_version,
      count(*) as version_count,
      max(g."created_at") as updated_at,
      coalesce((
        select jsonb_object_agg(y."label", y."version") from "better_supabase"."prompt_labels" y
        where coalesce(y."tenant_id"::text, '') = coalesce(page_prompts.tenant::text, '') and y."name" = g."name"
      ), '{}'::jsonb) as labels
    from "better_supabase"."prompt_versions" g
    where coalesce(g."tenant_id"::text, '') = coalesce(page_prompts.tenant::text, '')
    group by g."name"
  ) x
      where (not (v_filters -> 'name' is not null and jsonb_typeof(v_filters -> 'name') <> 'null' and not (jsonb_typeof(v_filters -> 'name') = 'array' and jsonb_array_length(v_filters -> 'name') = 0)) or (x.name)::text = any((case when jsonb_typeof(v_filters -> 'name') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'name')) else array[v_filters ->> 'name'] end)::text[]))
        and (not (v_filters -> 'label' is not null and jsonb_typeof(v_filters -> 'label') <> 'null' and not (jsonb_typeof(v_filters -> 'label') = 'array' and jsonb_array_length(v_filters -> 'label') = 0)) or x.labels ?| (case when jsonb_typeof(v_filters -> 'label') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'label')) else array[v_filters ->> 'label'] end))
        and (v_search is null or x.name ilike v_search)
        and (v_after is null or (x.version_count <= (v_after ->> 0)::bigint and ((x.version_count < (v_after ->> 0)::bigint) or (x.version_count = (v_after ->> 0)::bigint and x.name > (v_after ->> 1)::text))))
      order by x.version_count desc, x.name asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from (
    select g."name" as name,
      max(g."version") as latest_version,
      count(*) as version_count,
      max(g."created_at") as updated_at,
      coalesce((
        select jsonb_object_agg(y."label", y."version") from "better_supabase"."prompt_labels" y
        where coalesce(y."tenant_id"::text, '') = coalesce(page_prompts.tenant::text, '') and y."name" = g."name"
      ), '{}'::jsonb) as labels
    from "better_supabase"."prompt_versions" g
    where coalesce(g."tenant_id"::text, '') = coalesce(page_prompts.tenant::text, '')
    group by g."name"
  ) x
      where (not (v_filters -> 'name' is not null and jsonb_typeof(v_filters -> 'name') <> 'null' and not (jsonb_typeof(v_filters -> 'name') = 'array' and jsonb_array_length(v_filters -> 'name') = 0)) or (x.name)::text = any((case when jsonb_typeof(v_filters -> 'name') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'name')) else array[v_filters ->> 'name'] end)::text[]))
        and (not (v_filters -> 'label' is not null and jsonb_typeof(v_filters -> 'label') <> 'null' and not (jsonb_typeof(v_filters -> 'label') = 'array' and jsonb_array_length(v_filters -> 'label') = 0)) or x.labels ?| (case when jsonb_typeof(v_filters -> 'label') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'label')) else array[v_filters ->> 'label'] end))
        and (v_search is null or x.name ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_prompts"(uuid, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."page_prompts"(uuid, jsonb) to service_role;

-- blocks.prompts.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."create_prompt_version"(name text, template text, tenant uuid default null, variables jsonb default '[]'::jsonb, label text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_prompt_version"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."create_prompt_version"(text, text, uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "api"."create_prompt_version"(text, text, uuid, jsonb, text) to service_role;

create or replace function "api"."get_prompt"(name text, label text default 'production', version integer default null, tenant uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."get_prompt"($1, $2, $3, $4) $$;
revoke execute on function "api"."get_prompt"(text, text, integer, uuid) from public, anon, authenticated;
grant execute on function "api"."get_prompt"(text, text, integer, uuid) to service_role;

create or replace function "api"."set_prompt_label"(name text, label text, version integer, tenant uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_prompt_label"($1, $2, $3, $4) $$;
revoke execute on function "api"."set_prompt_label"(text, text, integer, uuid) from public, anon, authenticated;
grant execute on function "api"."set_prompt_label"(text, text, integer, uuid) to service_role;

create or replace function "api"."list_prompt_versions"(name text, tenant uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_prompt_versions"($1, $2) $$;
revoke execute on function "api"."list_prompt_versions"(text, uuid) from public, anon, authenticated;
grant execute on function "api"."list_prompt_versions"(text, uuid) to service_role;

create or replace function "api"."list_prompts"(tenant uuid default null, after text default null, max_rows integer default 50)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_prompts"($1, $2, $3) $$;
revoke execute on function "api"."list_prompts"(uuid, text, integer) from public, anon, authenticated;
grant execute on function "api"."list_prompts"(uuid, text, integer) to service_role;

create or replace function "api"."page_prompts"(tenant uuid default null, filters jsonb default '{}')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."page_prompts"($1, $2) $$;
revoke execute on function "api"."page_prompts"(uuid, jsonb) from public, anon, authenticated;
grant execute on function "api"."page_prompts"(uuid, jsonb) to service_role;
