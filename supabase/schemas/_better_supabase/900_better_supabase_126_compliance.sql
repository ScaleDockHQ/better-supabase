-- better-supabase module: compliance
-- @bsb-block compliance@4 managed
-- @bsb-hash sha256:f46fda32deaf6632c87410ffbbf98acaf1a5959cf9d77c6414451edc3638ab45
-- Compliance frameworks and their controls, evidence linked to controls (attachments or notes, with a validity date), recurring evidence tasks with assignees and an overdue state, a status rollup per framework, and policies published as frozen versions that members acknowledge through the acknowledgements block.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Compliance controls: frameworks of controls, evidence linked to them,
-- recurring evidence tasks, and versioned policies members acknowledge
-- through the acknowledgements block.

create table "better_supabase"."control_frameworks" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null constraint bsb_control_frameworks_key_check check ("key" ~ '^[a-z0-9][a-z0-9_.-]{0,62}$'),
  "name" text not null constraint bsb_control_frameworks_name_check check (length("name") >= 1 and length("name") <= 200),
  "kind" text not null default 'standard' constraint bsb_control_frameworks_kind_check check ("kind" in ('standard', 'legal', 'internal', 'contract')),
  "version" text constraint bsb_control_frameworks_version_check check ("version" is null or length("version") <= 50),
  "description" text constraint bsb_control_frameworks_description_check check ("description" is null or length("description") <= 4000),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key"),
  unique ("tenant_id", "id")
);
alter table "better_supabase"."control_frameworks" enable row level security;
revoke all on "better_supabase"."control_frameworks" from public, anon, authenticated;
grant select on "better_supabase"."control_frameworks" to authenticated;
grant all on "better_supabase"."control_frameworks" to service_role;
create policy bsb_control_frameworks_read on "better_supabase"."control_frameworks"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')));

create table "better_supabase"."controls" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "framework_id" uuid not null,
  "code" text not null constraint bsb_controls_code_check check (length("code") >= 1 and length("code") <= 50),
  "title" text not null constraint bsb_controls_title_check check (length("title") >= 1 and length("title") <= 200),
  "description" text constraint bsb_controls_description_check check ("description" is null or length("description") <= 10000),
  "owner_id" uuid,
  -- A control out of scope (excluded in the statement of applicability).
  "applicable" boolean not null default true,
  "source" text constraint bsb_controls_source_check check ("source" is null or length("source") >= 1 and length("source") <= 200),
  "jurisdiction" text constraint bsb_controls_jurisdiction_check check ("jurisdiction" is null or length("jurisdiction") >= 1 and length("jurisdiction") <= 200),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("framework_id", "code"),
  unique ("tenant_id", "id"),
  foreign key ("tenant_id", "framework_id") references "better_supabase"."control_frameworks" ("tenant_id", "id") on delete cascade
);
create index "controls_tenant_idx" on "better_supabase"."controls" ("tenant_id", "framework_id");
create index "controls_owner_idx" on "better_supabase"."controls" ("tenant_id", "owner_id") where "owner_id" is not null;
alter table "better_supabase"."controls" enable row level security;
revoke all on "better_supabase"."controls" from public, anon, authenticated;
grant select on "better_supabase"."controls" to authenticated;
grant all on "better_supabase"."controls" to service_role;
create policy bsb_controls_read on "better_supabase"."controls"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')));

create table "better_supabase"."evidence_tasks" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "control_id" uuid not null,
  "title" text not null constraint bsb_evidence_tasks_title_check check (length("title") >= 1 and length("title") <= 200),
  "assignee_id" uuid,
  -- Collecting evidence moves due_on this many days past the collection.
  "interval_days" integer not null constraint bsb_evidence_tasks_interval_days_check check ("interval_days" >= 1 and "interval_days" <= 3650),
  "due_on" date not null,
  "last_collected_at" timestamptz,
  -- The due date notify_overdue_evidence_tasks last reported, so each lapse notifies once.
  "notified_for" date,
  "active" boolean not null default true,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  foreign key ("tenant_id", "control_id") references "better_supabase"."controls" ("tenant_id", "id") on delete cascade
);
create index "evidence_tasks_parent_idx" on "better_supabase"."evidence_tasks" ("tenant_id", "control_id");
create index "evidence_tasks_assignee_idx" on "better_supabase"."evidence_tasks" ("tenant_id", "assignee_id", "due_on") where "assignee_id" is not null;
create index "evidence_tasks_due_idx" on "better_supabase"."evidence_tasks" ("due_on") where "active";
alter table "better_supabase"."evidence_tasks" enable row level security;
revoke all on "better_supabase"."evidence_tasks" from public, anon, authenticated;
grant select on "better_supabase"."evidence_tasks" to authenticated;
grant all on "better_supabase"."evidence_tasks" to service_role;
create policy bsb_evidence_tasks_read on "better_supabase"."evidence_tasks"
  for select to authenticated
  using ("assignee_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')));

create table "better_supabase"."control_evidence" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "control_id" uuid not null,
  "task_id" uuid references "better_supabase"."evidence_tasks" ("id") on delete set null,
  -- The file behind the evidence, an attachment on the control.
  "attachment_id" uuid references "better_supabase"."attachments" ("id") on delete cascade,
  "note" text constraint bsb_control_evidence_note_check check ("note" is null or length("note") <= 4000),
  "collected_by" uuid,
  "collected_at" timestamptz not null default now(),
  -- The last day the evidence counts; null counts until it is removed.
  "valid_until" date,
  constraint bsb_control_evidence_check check ("attachment_id" is not null or "note" is not null),
  foreign key ("tenant_id", "control_id") references "better_supabase"."controls" ("tenant_id", "id") on delete cascade
);
create index "control_evidence_parent_idx" on "better_supabase"."control_evidence" ("tenant_id", "control_id", "collected_at" desc);
create index "control_evidence_request_idx" on "better_supabase"."control_evidence" ("task_id") where "task_id" is not null;
create index "control_evidence_attachment_idx" on "better_supabase"."control_evidence" ("attachment_id") where "attachment_id" is not null;
alter table "better_supabase"."control_evidence" enable row level security;
revoke all on "better_supabase"."control_evidence" from public, anon, authenticated;
grant select on "better_supabase"."control_evidence" to authenticated;
grant all on "better_supabase"."control_evidence" to service_role;
create policy bsb_control_evidence_read on "better_supabase"."control_evidence"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')));

create table "better_supabase"."compliance_policies" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null constraint bsb_compliance_policies_key_check check ("key" ~ '^[a-z0-9][a-z0-9_.-]{0,62}$'),
  "title" text not null constraint bsb_compliance_policies_title_check check (length("title") >= 1 and length("title") <= 200),
  "owner_id" uuid,
  "requires_acknowledgement" boolean not null default true,
  -- The published version (versions block), frozen.
  "current_version_id" uuid references "better_supabase"."versions" ("id") on delete restrict,
  "version_number" integer,
  "published_at" timestamptz,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key"),
  unique ("tenant_id", "id")
);
create index "compliance_policies_version_idx" on "better_supabase"."compliance_policies" ("current_version_id") where "current_version_id" is not null;
alter table "better_supabase"."compliance_policies" enable row level security;
revoke all on "better_supabase"."compliance_policies" from public, anon, authenticated;
grant select on "better_supabase"."compliance_policies" to authenticated;
grant all on "better_supabase"."compliance_policies" to service_role;
create policy bsb_compliance_policies_read on "better_supabase"."compliance_policies"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')));

-- Creates or updates a framework (SOC 2, ISO 27001, an internal one) by key.
-- kind is standard, legal (a register of legal obligations), internal or
-- contract.

create or replace function "better_supabase"."save_control_framework"(tenant uuid, key text, name text, version text default null, description text default null, kind text default 'standard')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."control_frameworks"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_control_framework.tenant, 'compliance.manage'), false)) then
    raise exception 'not allowed to manage controls' using errcode = '42501', hint = 'CONTROL_FORBIDDEN';
  end if;
  if save_control_framework.kind is null or save_control_framework.kind not in ('standard', 'legal', 'internal', 'contract') then
    raise exception 'kind must be one of standard, legal, internal, contract' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  insert into "better_supabase"."control_frameworks" ("tenant_id", "key", "name", "kind", "version", "description")
  values (save_control_framework.tenant, save_control_framework.key, trim(save_control_framework.name), save_control_framework.kind, nullif(trim(save_control_framework.version), ''), nullif(trim(save_control_framework.description), ''))
  on conflict ("tenant_id", "key") do update
    set "name" = excluded."name", "kind" = excluded."kind", "version" = excluded."version",
      "description" = excluded."description", "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'kind', v_row."kind", 'version', v_row."version", 'description', v_row."description", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_control_framework"(uuid, text, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."save_control_framework"(uuid, text, text, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."list_control_frameworks"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'kind', x."kind", 'version', x."version", 'description', x."description", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."name"), '[]'::jsonb)
  from "better_supabase"."control_frameworks" x
  where x."tenant_id" = list_control_frameworks.tenant
$$;
revoke execute on function "better_supabase"."list_control_frameworks"(uuid) from public, anon;
grant execute on function "better_supabase"."list_control_frameworks"(uuid) to authenticated, service_role;

-- The frameworks as a keyset page, by name (ADR 1077). Row level security decides what the caller reads. filters is { kind (a value or a list), search (name and key), sort (name, key), direction, facet, count, limit, after, offset, paged, total, totalCap }.
create or replace function "better_supabase"."page_control_frameworks"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_control_frameworks.filters, '{}'::jsonb);
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
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'COMPLIANCE_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('kind') then
      raise exception 'facet is one of kind' using errcode = '22023', hint = 'COMPLIANCE_INVALID';
    end if;
    with s as (
      select (case v_facet when 'kind' then (x."kind"::text)::text end) as v
      from "better_supabase"."control_frameworks" x
      where x."tenant_id" = page_control_frameworks.tenant
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
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
      select 1 from "better_supabase"."control_frameworks" x
      where x."tenant_id" = page_control_frameworks.tenant
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'key') then
    raise exception 'sort is one of name, key' using errcode = '22023', hint = 'COMPLIANCE_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'COMPLIANCE_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMPLIANCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'kind', x."kind", 'version', x."version", 'description', x."description", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."control_frameworks" x
      where x."tenant_id" = page_control_frameworks.tenant
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_after is null or (x."name", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."name" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMPLIANCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'kind', x."kind", 'version', x."version", 'description', x."description", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."control_frameworks" x
      where x."tenant_id" = page_control_frameworks.tenant
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_after is null or (x."name" <= (v_after ->> 0)::text and ((x."name" < (v_after ->> 0)::text) or (x."name" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."name" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMPLIANCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'kind', x."kind", 'version', x."version", 'description', x."description", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."control_frameworks" x
      where x."tenant_id" = page_control_frameworks.tenant
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_after is null or (x."name", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."name" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMPLIANCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'kind', x."kind", 'version', x."version", 'description', x."description", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."control_frameworks" x
      where x."tenant_id" = page_control_frameworks.tenant
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_after is null or (x."name" <= (v_after ->> 0)::text and ((x."name" < (v_after ->> 0)::text) or (x."name" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."name" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'key' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMPLIANCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'kind', x."kind", 'version', x."version", 'description', x."description", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."key")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."control_frameworks" x
      where x."tenant_id" = page_control_frameworks.tenant
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_after is null or (x."key", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."key" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'key' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMPLIANCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'kind', x."kind", 'version', x."version", 'description', x."description", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."key")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."control_frameworks" x
      where x."tenant_id" = page_control_frameworks.tenant
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_after is null or (x."key" <= (v_after ->> 0)::text and ((x."key" < (v_after ->> 0)::text) or (x."key" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."key" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."control_frameworks" x
      where x."tenant_id" = page_control_frameworks.tenant
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_control_frameworks"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."page_control_frameworks"(uuid, jsonb) to authenticated, service_role;

-- One framework, or a not-found error. Row level security decides what the caller reads.
create or replace function "better_supabase"."get_control_framework"(framework_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."control_frameworks"%rowtype;
begin
  select * into v_row from "better_supabase"."control_frameworks" x where x."id" = get_control_framework.framework_id;
  if not found then
    raise exception 'framework not found' using errcode = 'P0002', hint = 'CONTROL_FRAMEWORK_NOT_FOUND';
  end if;
  
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'kind', v_row."kind", 'version', v_row."version", 'description', v_row."description", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."get_control_framework"(uuid) from public, anon;
grant execute on function "better_supabase"."get_control_framework"(uuid) to authenticated, service_role;

-- Creates a control in a framework, or changes one (control_id). Without
-- control_id, a control with the same code in the framework is updated.
-- source names where an obligation comes from (a law or a clause) and
-- jurisdiction where it applies.

create or replace function "better_supabase"."save_control"(framework_id uuid, code text, title text, description text default null, owner_id uuid default null, applicable boolean default true, control_id uuid default null, source text default null, jurisdiction text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_framework "better_supabase"."control_frameworks"%rowtype;
  v_row "better_supabase"."controls"%rowtype;
  v_new boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_framework from "better_supabase"."control_frameworks" x where x."id" = save_control.framework_id;
  if not found then
    raise exception 'framework not found' using errcode = 'P0002', hint = 'CONTROL_FRAMEWORK_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_framework."tenant_id", 'compliance.manage'), false)) then
    raise exception 'not allowed to manage controls' using errcode = '42501', hint = 'CONTROL_FORBIDDEN';
  end if;
  if nullif(trim(save_control.code), '') is null or nullif(trim(save_control.title), '') is null then
    raise exception 'a control needs a code and a title' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  if save_control.owner_id is not null and not exists (select 1 from "public"."memberships" m where m."organization_id" = v_framework."tenant_id" and m."user_id" = save_control.owner_id) then
    raise exception 'the owner must be a member of the organization' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  v_new := false;
  if save_control.control_id is null then
    v_new := not exists (select 1 from "better_supabase"."controls" x where x."framework_id" = v_framework."id" and x."code" = trim(save_control.code));
    insert into "better_supabase"."controls" ("tenant_id", "framework_id", "code", "title", "description", "owner_id", "source", "jurisdiction", "applicable")
    values (v_framework."tenant_id", v_framework."id", trim(save_control.code), trim(save_control.title), nullif(trim(save_control.description), ''), save_control.owner_id, nullif(trim(save_control.source), ''), nullif(trim(save_control.jurisdiction), ''), coalesce(save_control.applicable, true))
    on conflict ("framework_id", "code") do update
      set "title" = excluded."title", "description" = excluded."description", "source" = excluded."source", "jurisdiction" = excluded."jurisdiction",
        "owner_id" = excluded."owner_id", "applicable" = excluded."applicable", "updated_at" = now()
    returning * into v_row;
  else
    update "better_supabase"."controls" x set "code" = trim(save_control.code), "title" = trim(save_control.title),
      "description" = nullif(trim(save_control.description), ''), "source" = nullif(trim(save_control.source), ''), "jurisdiction" = nullif(trim(save_control.jurisdiction), ''), "owner_id" = save_control.owner_id,
      "applicable" = coalesce(save_control.applicable, true), "updated_at" = now()
      where x."id" = save_control.control_id and x."framework_id" = v_framework."id"
      returning * into v_row;
    if not found then
      raise exception 'control not found' using errcode = 'P0002', hint = 'CONTROL_NOT_FOUND';
    end if;
  end if;
  if v_new then
    perform "better_supabase".emit_event('control.created', jsonb_build_object('organizationId', v_row."tenant_id", 'controlId', v_row."id", 'frameworkId', v_row."framework_id", 'code', v_row."code"), 'controls/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/compliance');
  perform better_supabase.audit_event(
    event_type => 'control.created',
    category => 'data',
    target_type => 'control',
    record_id => v_row."id"::text,
    summary => 'created control ' || v_row."code",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'controlId', v_row."id", 'frameworkId', v_row."framework_id", 'code', v_row."code")
  );
  else
    perform "better_supabase".emit_event('control.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'controlId', v_row."id", 'frameworkId', v_row."framework_id", 'code', v_row."code"), 'controls/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/compliance');
  perform better_supabase.audit_event(
    event_type => 'control.updated',
    category => 'data',
    target_type => 'control',
    record_id => v_row."id"::text,
    summary => 'updated control ' || v_row."code",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'controlId', v_row."id", 'frameworkId', v_row."framework_id", 'code', v_row."code")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'frameworkId', v_row."framework_id", 'code', v_row."code", 'title', v_row."title", 'description', v_row."description", 'ownerId', v_row."owner_id", 'applicable', v_row."applicable", 'source', v_row."source", 'jurisdiction', v_row."jurisdiction", 'status', case
    when not v_row."applicable" then 'not_applicable'
    when exists (select 1 from "better_supabase"."evidence_tasks" st where st."control_id" = v_row."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = v_row."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = v_row."id") then 'failing'
    else 'not_started'
  end, 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_control"(uuid, text, text, text, uuid, boolean, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."save_control"(uuid, text, text, text, uuid, boolean, uuid, text, text) to authenticated, service_role;

-- A control with its evidence (the newest first) and its evidence tasks.
create or replace function "better_supabase"."get_control"(control_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_row "better_supabase"."controls"%rowtype;
begin
  select * into v_row from "better_supabase"."controls" x where x."id" = get_control.control_id;
  if not found then
    raise exception 'control not found' using errcode = 'P0002', hint = 'CONTROL_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'frameworkId', v_row."framework_id", 'code', v_row."code", 'title', v_row."title", 'description', v_row."description", 'ownerId', v_row."owner_id", 'applicable', v_row."applicable", 'source', v_row."source", 'jurisdiction', v_row."jurisdiction", 'status', case
    when not v_row."applicable" then 'not_applicable'
    when exists (select 1 from "better_supabase"."evidence_tasks" st where st."control_id" = v_row."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = v_row."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = v_row."id") then 'failing'
    else 'not_started'
  end, 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'evidence', (select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'controlId', y."control_id", 'evidenceTaskId', y."task_id", 'attachmentId', y."attachment_id", 'note', y."note", 'collectedBy', y."collected_by", 'collectedAt', y."collected_at", 'validUntil', y."valid_until", 'valid', (y."valid_until" is null or y."valid_until" >= current_date)) order by y."collected_at" desc), '[]'::jsonb)
      from (select * from "better_supabase"."control_evidence" z where z."control_id" = v_row."id" order by z."collected_at" desc limit 100) y),
    'tasks', (select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'controlId', y."control_id", 'title', y."title", 'assigneeId', y."assignee_id", 'intervalDays', y."interval_days", 'dueOn', y."due_on", 'lastCollectedAt', y."last_collected_at", 'active', y."active", 'overdue', (y."active" and y."due_on" < current_date), 'createdAt', y."created_at", 'updatedAt', y."updated_at") order by y."due_on"), '[]'::jsonb)
      from "better_supabase"."evidence_tasks" y where y."control_id" = v_row."id")
  );
end;
$$;
revoke execute on function "better_supabase"."get_control"(uuid) from public, anon;
grant execute on function "better_supabase"."get_control"(uuid) to authenticated, service_role;

-- The controls the caller can read, by framework and code. status filters on
-- the computed status.
create or replace function "better_supabase"."list_controls"(tenant uuid, framework_id uuid default null, status text default null, owner_id uuid default null, page_size integer default 200)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(x.doc order by x.framework, x.code), '[]'::jsonb)
  from (
    select y."framework_id" as framework, y."code" as code, jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'frameworkId', y."framework_id", 'code', y."code", 'title', y."title", 'description', y."description", 'ownerId', y."owner_id", 'applicable', y."applicable", 'source', y."source", 'jurisdiction', y."jurisdiction", 'status', case
    when not y."applicable" then 'not_applicable'
    when exists (select 1 from "better_supabase"."evidence_tasks" st where st."control_id" = y."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id") then 'failing'
    else 'not_started'
  end, 'createdAt', y."created_at", 'updatedAt', y."updated_at") as doc
    from "better_supabase"."controls" y
    where y."tenant_id" = list_controls.tenant
      and (list_controls.framework_id is null or y."framework_id" = list_controls.framework_id)
      and (list_controls.owner_id is null or y."owner_id" = list_controls.owner_id)
      and (list_controls.status is null or case
    when not y."applicable" then 'not_applicable'
    when exists (select 1 from "better_supabase"."evidence_tasks" st where st."control_id" = y."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id") then 'failing'
    else 'not_started'
  end = list_controls.status)
    order by y."framework_id", y."code"
    limit least(greatest(coalesce(list_controls.page_size, 200), 1), 1000)
  ) x
$$;
revoke execute on function "better_supabase"."list_controls"(uuid, uuid, text, uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_controls"(uuid, uuid, text, uuid, integer) to authenticated, service_role;

-- Records evidence for a control: an attachment on it, a note, or both. With
-- task_id it answers that recurring task, whose due date moves interval_days
-- past today; valid_until then defaults to that date. The task's assignee
-- may collect without the collect permission.
create or replace function "better_supabase"."add_control_evidence"(control_id uuid, attachment_id uuid default null, note text default null, valid_until date default null, task_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_control "better_supabase"."controls"%rowtype;
  v_task "better_supabase"."evidence_tasks"%rowtype;
  v_row "better_supabase"."control_evidence"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_control from "better_supabase"."controls" x where x."id" = add_control_evidence.control_id;
  if not found then
    raise exception 'control not found' using errcode = 'P0002', hint = 'CONTROL_NOT_FOUND';
  end if;
  if add_control_evidence.task_id is not null then
    select * into v_task from "better_supabase"."evidence_tasks" x
      where x."id" = add_control_evidence.task_id and x."control_id" = v_control."id"
      for update;
    if not found then
      raise exception 'the evidence task isn''t a task of this control' using errcode = 'P0002', hint = 'EVIDENCE_TASK_NOT_FOUND';
    end if;
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_control."tenant_id", 'compliance.collect'), false)) or (v_task."assignee_id" is not null and coalesce(v_task."assignee_id" = auth.uid(), false))) then
    raise exception 'not allowed to collect evidence' using errcode = '42501', hint = 'CONTROL_FORBIDDEN';
  end if;
  if add_control_evidence.attachment_id is null and nullif(trim(add_control_evidence.note), '') is null then
    raise exception 'evidence needs an attachment or a note' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  if add_control_evidence.attachment_id is not null and not exists (
    select 1 from "better_supabase"."attachments" a
    where a."id" = add_control_evidence.attachment_id
      and a."tenant_id" = v_control."tenant_id"
  ) then
    raise exception 'the attachment isn''t a file in this organization' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  insert into "better_supabase"."control_evidence" ("tenant_id", "control_id", "task_id", "attachment_id", "note", "collected_by", "valid_until")
  values (v_control."tenant_id", v_control."id", v_task."id", add_control_evidence.attachment_id,
    nullif(trim(add_control_evidence.note), ''), auth.uid(),
    coalesce(add_control_evidence.valid_until, current_date + v_task."interval_days"))
  returning * into v_row;
  if v_task."id" is not null then
    update "better_supabase"."evidence_tasks" x set "due_on" = current_date + x."interval_days", "last_collected_at" = now(),
      "notified_for" = null, "updated_at" = now()
      where x."id" = v_task."id";
  end if;
  perform "better_supabase".emit_event('control.evidence_added', jsonb_build_object('organizationId', v_row."tenant_id", 'controlId', v_row."control_id", 'evidenceId', v_row."id", 'evidenceTaskId', v_row."task_id"), 'controls/' || v_row."control_id"::text, (v_row."tenant_id")::text, null, 'better-supabase/compliance');
  perform better_supabase.audit_event(
    event_type => 'control.evidence_added',
    category => 'data',
    target_type => 'control',
    record_id => v_row."control_id"::text,
    summary => 'collected evidence for control ' || v_control."code",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'controlId', v_row."control_id", 'evidenceId', v_row."id", 'evidenceTaskId', v_row."task_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'controlId', v_row."control_id", 'evidenceTaskId', v_row."task_id", 'attachmentId', v_row."attachment_id", 'note', v_row."note", 'collectedBy', v_row."collected_by", 'collectedAt', v_row."collected_at", 'validUntil', v_row."valid_until", 'valid', (v_row."valid_until" is null or v_row."valid_until" >= current_date));
end;
$$;
revoke execute on function "better_supabase"."add_control_evidence"(uuid, uuid, text, date, uuid) from public, anon;
grant execute on function "better_supabase"."add_control_evidence"(uuid, uuid, text, date, uuid) to authenticated, service_role;

create or replace function "better_supabase"."remove_control_evidence"(evidence_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."control_evidence"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."control_evidence" x where x."id" = remove_control_evidence.evidence_id;
  if not found then
    raise exception 'evidence not found' using errcode = 'P0002', hint = 'CONTROL_EVIDENCE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'compliance.manage'), false)) then
    raise exception 'not allowed to manage controls' using errcode = '42501', hint = 'CONTROL_FORBIDDEN';
  end if;
  delete from "better_supabase"."control_evidence" x where x."id" = v_row."id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'controlId', v_row."control_id", 'evidenceTaskId', v_row."task_id", 'attachmentId', v_row."attachment_id", 'note', v_row."note", 'collectedBy', v_row."collected_by", 'collectedAt', v_row."collected_at", 'validUntil', v_row."valid_until", 'valid', (v_row."valid_until" is null or v_row."valid_until" >= current_date));
end;
$$;
revoke execute on function "better_supabase"."remove_control_evidence"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_control_evidence"(uuid) to authenticated, service_role;

-- Creates a recurring evidence task on a control, or changes one (task_id).
-- due_on defaults to today: the first evidence is due now.
create or replace function "better_supabase"."save_evidence_task"(control_id uuid, title text, interval_days integer, due_on date default null, assignee_id uuid default null, active boolean default true, task_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_control "better_supabase"."controls"%rowtype;
  v_row "better_supabase"."evidence_tasks"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_control from "better_supabase"."controls" x where x."id" = save_evidence_task.control_id;
  if not found then
    raise exception 'control not found' using errcode = 'P0002', hint = 'CONTROL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_control."tenant_id", 'compliance.manage'), false)) then
    raise exception 'not allowed to manage controls' using errcode = '42501', hint = 'CONTROL_FORBIDDEN';
  end if;
  if nullif(trim(save_evidence_task.title), '') is null then
    raise exception 'an evidence task needs a title' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  if save_evidence_task.interval_days is null or save_evidence_task.interval_days not between 1 and 3650 then
    raise exception 'interval_days must be from 1 to 3650' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  if save_evidence_task.assignee_id is not null and not exists (select 1 from "public"."memberships" m where m."organization_id" = v_control."tenant_id" and m."user_id" = save_evidence_task.assignee_id) then
    raise exception 'the assignee must be a member of the organization' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  if save_evidence_task.task_id is null then
    insert into "better_supabase"."evidence_tasks" ("tenant_id", "control_id", "title", "assignee_id", "interval_days", "due_on", "active")
    values (v_control."tenant_id", v_control."id", trim(save_evidence_task.title), save_evidence_task.assignee_id,
      save_evidence_task.interval_days, coalesce(save_evidence_task.due_on, current_date), coalesce(save_evidence_task.active, true))
    returning * into v_row;
  else
    update "better_supabase"."evidence_tasks" x set "title" = trim(save_evidence_task.title), "assignee_id" = save_evidence_task.assignee_id,
      "interval_days" = save_evidence_task.interval_days, "due_on" = coalesce(save_evidence_task.due_on, x."due_on"),
      "active" = coalesce(save_evidence_task.active, true), "updated_at" = now()
      where x."id" = save_evidence_task.task_id and x."control_id" = v_control."id"
      returning * into v_row;
    if not found then
      raise exception 'the evidence task isn''t a task of this control' using errcode = 'P0002', hint = 'EVIDENCE_TASK_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'controlId', v_row."control_id", 'title', v_row."title", 'assigneeId', v_row."assignee_id", 'intervalDays', v_row."interval_days", 'dueOn', v_row."due_on", 'lastCollectedAt', v_row."last_collected_at", 'active', v_row."active", 'overdue', (v_row."active" and v_row."due_on" < current_date), 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_evidence_task"(uuid, text, integer, date, uuid, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."save_evidence_task"(uuid, text, integer, date, uuid, boolean, uuid) to authenticated, service_role;

-- The evidence tasks the caller can read, the earliest due first.
create or replace function "better_supabase"."list_evidence_tasks"(tenant uuid, control_id uuid default null, assignee_id uuid default null, overdue_only boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'controlId', x."control_id", 'title', x."title", 'assigneeId', x."assignee_id", 'intervalDays', x."interval_days", 'dueOn', x."due_on", 'lastCollectedAt', x."last_collected_at", 'active', x."active", 'overdue', (x."active" and x."due_on" < current_date), 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('controlCode', y."code", 'controlTitle', y."title") order by x."due_on", x."id"), '[]'::jsonb)
  from "better_supabase"."evidence_tasks" x
  join "better_supabase"."controls" y on y."id" = x."control_id"
  where x."tenant_id" = list_evidence_tasks.tenant
    and (list_evidence_tasks.control_id is null or x."control_id" = list_evidence_tasks.control_id)
    and (list_evidence_tasks.assignee_id is null or x."assignee_id" = list_evidence_tasks.assignee_id)
    and (not coalesce(list_evidence_tasks.overdue_only, false) or (x."active" and x."due_on" < current_date))
$$;
revoke execute on function "better_supabase"."list_evidence_tasks"(uuid, uuid, uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_evidence_tasks"(uuid, uuid, uuid, boolean) to authenticated, service_role;

-- The evidence tasks as a keyset page, the earliest due first (ADR 1077). Row level security decides what the caller reads. filters is { controlId, assigneeId (each a value or a list), overdue (true keeps the overdue tasks), search (title), sort (dueOn, title), direction, facet, count, limit, after, offset, paged, total, totalCap }.
create or replace function "better_supabase"."page_evidence_tasks"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_evidence_tasks.filters, '{}'::jsonb);
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
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'COMPLIANCE_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('controlId') then
      raise exception 'facet is one of controlId' using errcode = '22023', hint = 'COMPLIANCE_INVALID';
    end if;
    with s as (
      select (case v_facet when 'controlId' then (x."control_id"::text)::text end) as v
      from "better_supabase"."evidence_tasks" x
      where x."tenant_id" = page_evidence_tasks.tenant
        and (not (v_filters -> 'controlId' is not null and jsonb_typeof(v_filters -> 'controlId') <> 'null' and not (jsonb_typeof(v_filters -> 'controlId') = 'array' and jsonb_array_length(v_filters -> 'controlId') = 0)) or x."control_id"::text = any((case when jsonb_typeof(v_filters -> 'controlId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'controlId')) else array[v_filters ->> 'controlId'] end)::text[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or x."assignee_id"::text = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{overdue,0}', v_filters ->> 'overdue'), '') = 'true', false) or (x."active" and x."due_on" < current_date))
        and (v_search is null or x."title" ilike v_search)
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
      select 1 from "better_supabase"."evidence_tasks" x
      where x."tenant_id" = page_evidence_tasks.tenant
        and (not (v_filters -> 'controlId' is not null and jsonb_typeof(v_filters -> 'controlId') <> 'null' and not (jsonb_typeof(v_filters -> 'controlId') = 'array' and jsonb_array_length(v_filters -> 'controlId') = 0)) or x."control_id"::text = any((case when jsonb_typeof(v_filters -> 'controlId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'controlId')) else array[v_filters ->> 'controlId'] end)::text[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or x."assignee_id"::text = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{overdue,0}', v_filters ->> 'overdue'), '') = 'true', false) or (x."active" and x."due_on" < current_date))
        and (v_search is null or x."title" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('dueOn', 'title') then
    raise exception 'sort is one of dueOn, title' using errcode = '22023', hint = 'COMPLIANCE_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'COMPLIANCE_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMPLIANCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'controlId', x."control_id", 'title', x."title", 'assigneeId', x."assignee_id", 'intervalDays', x."interval_days", 'dueOn', x."due_on", 'lastCollectedAt', x."last_collected_at", 'active', x."active", 'overdue', (x."active" and x."due_on" < current_date), 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('controlCode', (select y."code" from "better_supabase"."controls" y where y."id" = x."control_id"), 'controlTitle', (select y."title" from "better_supabase"."controls" y where y."id" = x."control_id")) as j, jsonb_build_array((x."due_on")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."evidence_tasks" x
      where x."tenant_id" = page_evidence_tasks.tenant
        and (not (v_filters -> 'controlId' is not null and jsonb_typeof(v_filters -> 'controlId') <> 'null' and not (jsonb_typeof(v_filters -> 'controlId') = 'array' and jsonb_array_length(v_filters -> 'controlId') = 0)) or x."control_id"::text = any((case when jsonb_typeof(v_filters -> 'controlId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'controlId')) else array[v_filters ->> 'controlId'] end)::text[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or x."assignee_id"::text = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{overdue,0}', v_filters ->> 'overdue'), '') = 'true', false) or (x."active" and x."due_on" < current_date))
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."due_on", x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by x."due_on" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMPLIANCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'controlId', x."control_id", 'title', x."title", 'assigneeId', x."assignee_id", 'intervalDays', x."interval_days", 'dueOn', x."due_on", 'lastCollectedAt', x."last_collected_at", 'active', x."active", 'overdue', (x."active" and x."due_on" < current_date), 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('controlCode', (select y."code" from "better_supabase"."controls" y where y."id" = x."control_id"), 'controlTitle', (select y."title" from "better_supabase"."controls" y where y."id" = x."control_id")) as j, jsonb_build_array((x."due_on")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."evidence_tasks" x
      where x."tenant_id" = page_evidence_tasks.tenant
        and (not (v_filters -> 'controlId' is not null and jsonb_typeof(v_filters -> 'controlId') <> 'null' and not (jsonb_typeof(v_filters -> 'controlId') = 'array' and jsonb_array_length(v_filters -> 'controlId') = 0)) or x."control_id"::text = any((case when jsonb_typeof(v_filters -> 'controlId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'controlId')) else array[v_filters ->> 'controlId'] end)::text[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or x."assignee_id"::text = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{overdue,0}', v_filters ->> 'overdue'), '') = 'true', false) or (x."active" and x."due_on" < current_date))
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."due_on" <= (v_after ->> 0)::date and ((x."due_on" < (v_after ->> 0)::date) or (x."due_on" = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by x."due_on" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'dueOn' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMPLIANCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'controlId', x."control_id", 'title', x."title", 'assigneeId', x."assignee_id", 'intervalDays', x."interval_days", 'dueOn', x."due_on", 'lastCollectedAt', x."last_collected_at", 'active', x."active", 'overdue', (x."active" and x."due_on" < current_date), 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('controlCode', (select y."code" from "better_supabase"."controls" y where y."id" = x."control_id"), 'controlTitle', (select y."title" from "better_supabase"."controls" y where y."id" = x."control_id")) as j, jsonb_build_array((x."due_on")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."evidence_tasks" x
      where x."tenant_id" = page_evidence_tasks.tenant
        and (not (v_filters -> 'controlId' is not null and jsonb_typeof(v_filters -> 'controlId') <> 'null' and not (jsonb_typeof(v_filters -> 'controlId') = 'array' and jsonb_array_length(v_filters -> 'controlId') = 0)) or x."control_id"::text = any((case when jsonb_typeof(v_filters -> 'controlId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'controlId')) else array[v_filters ->> 'controlId'] end)::text[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or x."assignee_id"::text = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{overdue,0}', v_filters ->> 'overdue'), '') = 'true', false) or (x."active" and x."due_on" < current_date))
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."due_on", x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by x."due_on" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'dueOn' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMPLIANCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'controlId', x."control_id", 'title', x."title", 'assigneeId', x."assignee_id", 'intervalDays', x."interval_days", 'dueOn', x."due_on", 'lastCollectedAt', x."last_collected_at", 'active', x."active", 'overdue', (x."active" and x."due_on" < current_date), 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('controlCode', (select y."code" from "better_supabase"."controls" y where y."id" = x."control_id"), 'controlTitle', (select y."title" from "better_supabase"."controls" y where y."id" = x."control_id")) as j, jsonb_build_array((x."due_on")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."evidence_tasks" x
      where x."tenant_id" = page_evidence_tasks.tenant
        and (not (v_filters -> 'controlId' is not null and jsonb_typeof(v_filters -> 'controlId') <> 'null' and not (jsonb_typeof(v_filters -> 'controlId') = 'array' and jsonb_array_length(v_filters -> 'controlId') = 0)) or x."control_id"::text = any((case when jsonb_typeof(v_filters -> 'controlId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'controlId')) else array[v_filters ->> 'controlId'] end)::text[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or x."assignee_id"::text = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{overdue,0}', v_filters ->> 'overdue'), '') = 'true', false) or (x."active" and x."due_on" < current_date))
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."due_on" <= (v_after ->> 0)::date and ((x."due_on" < (v_after ->> 0)::date) or (x."due_on" = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by x."due_on" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMPLIANCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'controlId', x."control_id", 'title', x."title", 'assigneeId', x."assignee_id", 'intervalDays', x."interval_days", 'dueOn', x."due_on", 'lastCollectedAt', x."last_collected_at", 'active', x."active", 'overdue', (x."active" and x."due_on" < current_date), 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('controlCode', (select y."code" from "better_supabase"."controls" y where y."id" = x."control_id"), 'controlTitle', (select y."title" from "better_supabase"."controls" y where y."id" = x."control_id")) as j, jsonb_build_array((x."title")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."evidence_tasks" x
      where x."tenant_id" = page_evidence_tasks.tenant
        and (not (v_filters -> 'controlId' is not null and jsonb_typeof(v_filters -> 'controlId') <> 'null' and not (jsonb_typeof(v_filters -> 'controlId') = 'array' and jsonb_array_length(v_filters -> 'controlId') = 0)) or x."control_id"::text = any((case when jsonb_typeof(v_filters -> 'controlId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'controlId')) else array[v_filters ->> 'controlId'] end)::text[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or x."assignee_id"::text = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{overdue,0}', v_filters ->> 'overdue'), '') = 'true', false) or (x."active" and x."due_on" < current_date))
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."title", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."title" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMPLIANCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'controlId', x."control_id", 'title', x."title", 'assigneeId', x."assignee_id", 'intervalDays', x."interval_days", 'dueOn', x."due_on", 'lastCollectedAt', x."last_collected_at", 'active', x."active", 'overdue', (x."active" and x."due_on" < current_date), 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('controlCode', (select y."code" from "better_supabase"."controls" y where y."id" = x."control_id"), 'controlTitle', (select y."title" from "better_supabase"."controls" y where y."id" = x."control_id")) as j, jsonb_build_array((x."title")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."evidence_tasks" x
      where x."tenant_id" = page_evidence_tasks.tenant
        and (not (v_filters -> 'controlId' is not null and jsonb_typeof(v_filters -> 'controlId') <> 'null' and not (jsonb_typeof(v_filters -> 'controlId') = 'array' and jsonb_array_length(v_filters -> 'controlId') = 0)) or x."control_id"::text = any((case when jsonb_typeof(v_filters -> 'controlId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'controlId')) else array[v_filters ->> 'controlId'] end)::text[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or x."assignee_id"::text = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{overdue,0}', v_filters ->> 'overdue'), '') = 'true', false) or (x."active" and x."due_on" < current_date))
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."title" <= (v_after ->> 0)::text and ((x."title" < (v_after ->> 0)::text) or (x."title" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."title" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."evidence_tasks" x
      where x."tenant_id" = page_evidence_tasks.tenant
        and (not (v_filters -> 'controlId' is not null and jsonb_typeof(v_filters -> 'controlId') <> 'null' and not (jsonb_typeof(v_filters -> 'controlId') = 'array' and jsonb_array_length(v_filters -> 'controlId') = 0)) or x."control_id"::text = any((case when jsonb_typeof(v_filters -> 'controlId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'controlId')) else array[v_filters ->> 'controlId'] end)::text[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or x."assignee_id"::text = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{overdue,0}', v_filters ->> 'overdue'), '') = 'true', false) or (x."active" and x."due_on" < current_date))
        and (v_search is null or x."title" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_evidence_tasks"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."page_evidence_tasks"(uuid, jsonb) to authenticated, service_role;

-- One evidence task, or a not-found error. Row level security decides what the caller reads.
create or replace function "better_supabase"."get_evidence_task"(task_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."evidence_tasks"%rowtype;
begin
  select * into v_row from "better_supabase"."evidence_tasks" x where x."id" = get_evidence_task.task_id;
  if not found then
    raise exception 'evidence task not found' using errcode = 'P0002', hint = 'EVIDENCE_TASK_NOT_FOUND';
  end if;
  
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'controlId', v_row."control_id", 'title', v_row."title", 'assigneeId', v_row."assignee_id", 'intervalDays', v_row."interval_days", 'dueOn', v_row."due_on", 'lastCollectedAt', v_row."last_collected_at", 'active', v_row."active", 'overdue', (v_row."active" and v_row."due_on" < current_date), 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."get_evidence_task"(uuid) from public, anon;
grant execute on function "better_supabase"."get_evidence_task"(uuid) to authenticated, service_role;

-- The status rollup per framework: how many controls pass, fail, haven't
-- started or are out of scope, and how many evidence tasks are overdue.
create or replace function "better_supabase"."control_posture"(tenant uuid, framework_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'frameworkId', w."id", 'key', w."key", 'name', w."name", 'version', w."version",
    'total', coalesce(r.total, 0), 'passing', coalesce(r.passing, 0), 'failing', coalesce(r.failing, 0),
    'notStarted', coalesce(r.not_started, 0), 'notApplicable', coalesce(r.not_applicable, 0),
    'overdueTasks', (select count(*) from "better_supabase"."evidence_tasks" ot join "better_supabase"."controls" oc on oc."id" = ot."control_id" where oc."framework_id" = w."id" and (ot."active" and ot."due_on" < current_date))
  ) order by w."name"), '[]'::jsonb)
  from "better_supabase"."control_frameworks" w
  left join lateral (
    select count(*) as total,
      count(*) filter (where s.status = 'passing') as passing,
      count(*) filter (where s.status = 'failing') as failing,
      count(*) filter (where s.status = 'not_started') as not_started,
      count(*) filter (where s.status = 'not_applicable') as not_applicable
    from (select case
    when not y."applicable" then 'not_applicable'
    when exists (select 1 from "better_supabase"."evidence_tasks" st where st."control_id" = y."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id") then 'failing'
    else 'not_started'
  end as status from "better_supabase"."controls" y where y."framework_id" = w."id") s
  ) r on true
  where w."tenant_id" = control_posture.tenant
    and (control_posture.framework_id is null or w."id" = control_posture.framework_id)
$$;
revoke execute on function "better_supabase"."control_posture"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."control_posture"(uuid, uuid) to authenticated, service_role;

-- Reports each active evidence task past its due date once per lapse: an
-- evidence_task.missed event and, with notifications, a notification to the
-- assignee (or the control's owner). Run it daily from a job.
create or replace function "better_supabase"."notify_overdue_evidence_tasks"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_task "better_supabase"."evidence_tasks"%rowtype;
  v_owner uuid;
  v_claims text;
  v_count integer := 0;
begin
  for v_task in
    select * from "better_supabase"."evidence_tasks" x
    where (x."active" and x."due_on" < current_date) and x."notified_for" is distinct from x."due_on"
    for update skip locked
  loop
    select y."owner_id" into v_owner from "better_supabase"."controls" y where y."id" = v_task."control_id";
    perform "better_supabase".emit_event('evidence_task.missed', jsonb_build_object('organizationId', v_task."tenant_id", 'evidenceTaskId', v_task."id", 'controlId', v_task."control_id", 'assigneeId', v_task."assignee_id", 'dueOn', v_task."due_on"), 'evidence-tasks/' || v_task."id"::text, (v_task."tenant_id")::text, null, 'better-supabase/compliance');
  perform better_supabase.audit_event(
    event_type => 'evidence_task.missed',
    category => 'data',
    target_type => 'evidence_task',
    record_id => v_task."id"::text,
    summary => 'evidence task overdue: ' || v_task."title",
    tenant => (v_task."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_task."tenant_id", 'evidenceTaskId', v_task."id", 'controlId', v_task."control_id", 'assigneeId', v_task."assignee_id", 'dueOn', v_task."due_on")
  );
    if coalesce(v_task."assignee_id", v_owner) is not null then
      if better_supabase.import_run() is null then
        v_claims := current_setting('request.jwt.claims', true);
        perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
        perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'evidence_task.missed',
        'tenant', v_task."tenant_id",
        'actor', null,
        'subject_type', 'control',
        'subject_id', v_task."control_id"::text,
        'summary', v_task."title",
        'recipients', to_jsonb(array[coalesce(v_task."assignee_id", v_owner)]),
        'key', 'evidence_task.missed:' || v_task."id"::text || ':' || v_task."due_on"::text,
        'data', jsonb_build_object('evidenceTaskId', v_task."id", 'dueOn', v_task."due_on")
      ));
        perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      end if;
    end if;
    update "better_supabase"."evidence_tasks" x set "notified_for" = v_task."due_on" where x."id" = v_task."id";
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."notify_overdue_evidence_tasks"() from public, anon, authenticated;
grant execute on function "better_supabase"."notify_overdue_evidence_tasks"() to service_role;

-- Creates a policy by key, or changes one (policy_id). Its text lives in the
-- versions publish_compliance_policy writes. A policy that requires
-- acknowledgement is assigned once to every member, whatever their role
-- (acknowledgements block); turning the requirement off removes that
-- assignment.
create or replace function "better_supabase"."save_compliance_policy"(tenant uuid, key text, title text, owner_id uuid default null, requires_acknowledgement boolean default true, policy_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."compliance_policies"%rowtype;
  v_required boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_compliance_policy.tenant, 'compliance.manage'), false)) then
    raise exception 'not allowed to manage policies' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  if save_compliance_policy.owner_id is not null and not exists (
    select 1 from "public"."memberships" m where m."organization_id" = save_compliance_policy.tenant and m."user_id" = save_compliance_policy.owner_id
  ) then
    raise exception 'the owner must be a member of the organization' using errcode = '22023', hint = 'COMPLIANCE_POLICY_INVALID';
  end if;
  select x."requires_acknowledgement" and x."archived_at" is null into v_required from "better_supabase"."compliance_policies" x
    where x."tenant_id" = save_compliance_policy.tenant
      and (x."id" = save_compliance_policy.policy_id or (save_compliance_policy.policy_id is null and x."key" = save_compliance_policy.key));
  if save_compliance_policy.policy_id is null then
    insert into "better_supabase"."compliance_policies" ("tenant_id", "key", "title", "owner_id", "requires_acknowledgement")
    values (save_compliance_policy.tenant, save_compliance_policy.key, trim(save_compliance_policy.title), save_compliance_policy.owner_id, coalesce(save_compliance_policy.requires_acknowledgement, true))
    on conflict ("tenant_id", "key") do update
      set "title" = excluded."title", "owner_id" = excluded."owner_id",
        "requires_acknowledgement" = excluded."requires_acknowledgement", "updated_at" = now()
    returning * into v_row;
  else
    update "better_supabase"."compliance_policies" x set "key" = save_compliance_policy.key, "title" = trim(save_compliance_policy.title), "owner_id" = save_compliance_policy.owner_id,
      "requires_acknowledgement" = coalesce(save_compliance_policy.requires_acknowledgement, true), "updated_at" = now()
      where x."id" = save_compliance_policy.policy_id and x."tenant_id" = save_compliance_policy.tenant
      returning * into v_row;
    if not found then
      raise exception 'policy not found' using errcode = 'P0002', hint = 'COMPLIANCE_POLICY_NOT_FOUND';
    end if;
  end if;
  if v_row."requires_acknowledgement" and v_row."archived_at" is null and v_required is distinct from true then
    perform "better_supabase"."place_acknowledgement_assignment"(v_row."tenant_id", 'compliance_policy', v_row."id"::text, 'role', '*', null);
  elsif not v_row."requires_acknowledgement" and v_required then
    perform "better_supabase"."drop_acknowledgement_assignment"(v_row."tenant_id", 'compliance_policy', v_row."id"::text, 'role', '*');
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'ownerId', v_row."owner_id", 'requiresAcknowledgement', v_row."requires_acknowledgement", 'versionId', v_row."current_version_id", 'versionNumber', v_row."version_number", 'publishedAt', v_row."published_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."acknowledgements" ack where ack."subject_type" = 'compliance_policy' and ack."subject_id" = v_row."id"::text and ack."version_id" = v_row."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."acknowledgements" ack join "public"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."subject_type" = 'compliance_policy' and ack."subject_id" = v_row."id"::text and ack."version_id" = v_row."current_version_id"), 'memberCount', (select count(*) from "public"."memberships" pm where pm."organization_id" = v_row."tenant_id"));
end;
$$;
revoke execute on function "better_supabase"."save_compliance_policy"(uuid, text, text, uuid, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."save_compliance_policy"(uuid, text, text, uuid, boolean, uuid) to authenticated, service_role;

-- Publishes the policy text as a new frozen version (versions block) and
-- makes it current. Members acknowledge each published version again, through
-- acknowledge in the acknowledgements block.
create or replace function "better_supabase"."publish_compliance_policy"(policy_id uuid, content jsonb, label text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."compliance_policies"%rowtype;
  v_version jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."compliance_policies" x where x."id" = publish_compliance_policy.policy_id for update;
  if not found then
    raise exception 'policy not found' using errcode = 'P0002', hint = 'COMPLIANCE_POLICY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'compliance.manage'), false)) then
    raise exception 'not allowed to manage policies' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'an archived policy can''t be published' using errcode = '55000', hint = 'COMPLIANCE_POLICY_ARCHIVED';
  end if;
  if publish_compliance_policy.content is null or jsonb_typeof(publish_compliance_policy.content) <> 'object' then
    raise exception 'content must be an object' using errcode = '22023', hint = 'COMPLIANCE_POLICY_INVALID';
  end if;
  v_version := "better_supabase"."version_insert"(
    v_row."tenant_id", 'compliance_policy', v_row."id"::text, publish_compliance_policy.content,
    null, coalesce(publish_compliance_policy.label, v_row."title"), 'manual', true, auth.uid()
  );
  update "better_supabase"."compliance_policies" x set "current_version_id" = (v_version ->> 'id')::uuid,
    "version_number" = (v_version ->> 'number')::integer, "published_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  perform "better_supabase".emit_event('compliance_policy.published', jsonb_build_object('organizationId', v_row."tenant_id", 'policyId', v_row."id", 'versionId', v_row."current_version_id", 'number', v_row."version_number"), 'policies/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/compliance');
  perform better_supabase.audit_event(
    event_type => 'compliance_policy.published',
    category => 'data',
    target_type => 'policy',
    record_id => v_row."id"::text,
    summary => 'published policy ' || v_row."title" || ' version ' || v_row."version_number"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'policyId', v_row."id", 'versionId', v_row."current_version_id", 'number', v_row."version_number")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'ownerId', v_row."owner_id", 'requiresAcknowledgement', v_row."requires_acknowledgement", 'versionId', v_row."current_version_id", 'versionNumber', v_row."version_number", 'publishedAt', v_row."published_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."acknowledgements" ack where ack."subject_type" = 'compliance_policy' and ack."subject_id" = v_row."id"::text and ack."version_id" = v_row."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."acknowledgements" ack join "public"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."subject_type" = 'compliance_policy' and ack."subject_id" = v_row."id"::text and ack."version_id" = v_row."current_version_id"), 'memberCount', (select count(*) from "public"."memberships" pm where pm."organization_id" = v_row."tenant_id"));
end;
$$;
revoke execute on function "better_supabase"."publish_compliance_policy"(uuid, jsonb, text) from public, anon;
grant execute on function "better_supabase"."publish_compliance_policy"(uuid, jsonb, text) to authenticated, service_role;

-- Archives a policy and removes its every-member assignment, so members stop
-- seeing it as pending.
create or replace function "better_supabase"."archive_compliance_policy"(policy_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."compliance_policies"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."compliance_policies" x where x."id" = archive_compliance_policy.policy_id for update;
  if not found then
    raise exception 'policy not found' using errcode = 'P0002', hint = 'COMPLIANCE_POLICY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'compliance.manage'), false)) then
    raise exception 'not allowed to manage policies' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  update "better_supabase"."compliance_policies" x set "archived_at" = coalesce(x."archived_at", now()), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  perform "better_supabase"."drop_acknowledgement_assignment"(v_row."tenant_id", 'compliance_policy', v_row."id"::text, 'role', '*');
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'ownerId', v_row."owner_id", 'requiresAcknowledgement', v_row."requires_acknowledgement", 'versionId', v_row."current_version_id", 'versionNumber', v_row."version_number", 'publishedAt', v_row."published_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."acknowledgements" ack where ack."subject_type" = 'compliance_policy' and ack."subject_id" = v_row."id"::text and ack."version_id" = v_row."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."acknowledgements" ack join "public"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."subject_type" = 'compliance_policy' and ack."subject_id" = v_row."id"::text and ack."version_id" = v_row."current_version_id"), 'memberCount', (select count(*) from "public"."memberships" pm where pm."organization_id" = v_row."tenant_id"));
end;
$$;
revoke execute on function "better_supabase"."archive_compliance_policy"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_compliance_policy"(uuid) to authenticated, service_role;

-- Restores an archived policy and places its every-member assignment again
-- when it needs an acknowledgement.
create or replace function "better_supabase"."restore_compliance_policy"(policy_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."compliance_policies"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."compliance_policies" x where x."id" = restore_compliance_policy.policy_id for update;
  if not found then
    raise exception 'policy not found' using errcode = 'P0002', hint = 'COMPLIANCE_POLICY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'compliance.manage'), false)) then
    raise exception 'not allowed to manage policies' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  if v_row."archived_at" is not null then
    update "better_supabase"."compliance_policies" x set "archived_at" = null, "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    if v_row."requires_acknowledgement" then
      perform "better_supabase"."place_acknowledgement_assignment"(v_row."tenant_id", 'compliance_policy', v_row."id"::text, 'role', '*', null);
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'ownerId', v_row."owner_id", 'requiresAcknowledgement', v_row."requires_acknowledgement", 'versionId', v_row."current_version_id", 'versionNumber', v_row."version_number", 'publishedAt', v_row."published_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."acknowledgements" ack where ack."subject_type" = 'compliance_policy' and ack."subject_id" = v_row."id"::text and ack."version_id" = v_row."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."acknowledgements" ack join "public"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."subject_type" = 'compliance_policy' and ack."subject_id" = v_row."id"::text and ack."version_id" = v_row."current_version_id"), 'memberCount', (select count(*) from "public"."memberships" pm where pm."organization_id" = v_row."tenant_id"));
end;
$$;
revoke execute on function "better_supabase"."restore_compliance_policy"(uuid) from public, anon;
grant execute on function "better_supabase"."restore_compliance_policy"(uuid) to authenticated, service_role;

-- The policies, with the caller's acknowledgement of each current version
-- and how many members acknowledged it. list_my_acknowledgements in the
-- acknowledgements block lists the ones the caller still has to acknowledge.
create or replace function "better_supabase"."list_compliance_policies"(tenant uuid, include_archived boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_compliance_policies.tenant, 'compliance.read'), false)) then
    raise exception 'not allowed to read policies' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'ownerId', x."owner_id", 'requiresAcknowledgement', x."requires_acknowledgement", 'versionId', x."current_version_id", 'versionNumber', x."version_number", 'publishedAt', x."published_at", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."acknowledgements" ack where ack."subject_type" = 'compliance_policy' and ack."subject_id" = x."id"::text and ack."version_id" = x."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."acknowledgements" ack join "public"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."subject_type" = 'compliance_policy' and ack."subject_id" = x."id"::text and ack."version_id" = x."current_version_id"), 'memberCount', (select count(*) from "public"."memberships" pm where pm."organization_id" = x."tenant_id")) order by x."title"), '[]'::jsonb)
    from "better_supabase"."compliance_policies" x
    where x."tenant_id" = list_compliance_policies.tenant
      and (coalesce(list_compliance_policies.include_archived, false) or x."archived_at" is null)
  );
end;
$$;
revoke execute on function "better_supabase"."list_compliance_policies"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_compliance_policies"(uuid, boolean) to authenticated, service_role;

-- The policies as a keyset page, by title, with the caller's acknowledgement of each current version (ADR 1077). filters is { ownerId, requiresAcknowledgement (each a value or a list), archived, search (title and key), sort (title, publishedAt), direction, facet, count, limit, after, offset, paged, total, totalCap }.
create or replace function "better_supabase"."page_compliance_policies"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_compliance_policies.filters, '{}'::jsonb);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', page_compliance_policies.tenant, 'compliance.read'), false)) then
    raise exception 'not allowed to read policies' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'COMPLIANCE_POLICY_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('requiresAcknowledgement') then
      raise exception 'facet is one of requiresAcknowledgement' using errcode = '22023', hint = 'COMPLIANCE_POLICY_INVALID';
    end if;
    with s as (
      select (case v_facet when 'requiresAcknowledgement' then (x."requires_acknowledgement"::text)::text end) as v
      from "better_supabase"."compliance_policies" x
      where x."tenant_id" = page_compliance_policies.tenant
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."title" ilike v_search or x."key" ilike v_search)
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'requiresAcknowledgement' is not null and jsonb_typeof(v_filters -> 'requiresAcknowledgement') <> 'null' and not (jsonb_typeof(v_filters -> 'requiresAcknowledgement') = 'array' and jsonb_array_length(v_filters -> 'requiresAcknowledgement') = 0)) or x."requires_acknowledgement"::text = any((case when jsonb_typeof(v_filters -> 'requiresAcknowledgement') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'requiresAcknowledgement')) else array[v_filters ->> 'requiresAcknowledgement'] end)::text[]))
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
      select 1 from "better_supabase"."compliance_policies" x
      where x."tenant_id" = page_compliance_policies.tenant
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."title" ilike v_search or x."key" ilike v_search)
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'requiresAcknowledgement' is not null and jsonb_typeof(v_filters -> 'requiresAcknowledgement') <> 'null' and not (jsonb_typeof(v_filters -> 'requiresAcknowledgement') = 'array' and jsonb_array_length(v_filters -> 'requiresAcknowledgement') = 0)) or x."requires_acknowledgement"::text = any((case when jsonb_typeof(v_filters -> 'requiresAcknowledgement') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'requiresAcknowledgement')) else array[v_filters ->> 'requiresAcknowledgement'] end)::text[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('title', 'publishedAt') then
    raise exception 'sort is one of title, publishedAt' using errcode = '22023', hint = 'COMPLIANCE_POLICY_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'COMPLIANCE_POLICY_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMPLIANCE_POLICY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'ownerId', x."owner_id", 'requiresAcknowledgement', x."requires_acknowledgement", 'versionId', x."current_version_id", 'versionNumber', x."version_number", 'publishedAt', x."published_at", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."acknowledgements" ack where ack."subject_type" = 'compliance_policy' and ack."subject_id" = x."id"::text and ack."version_id" = x."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."acknowledgements" ack join "public"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."subject_type" = 'compliance_policy' and ack."subject_id" = x."id"::text and ack."version_id" = x."current_version_id"), 'memberCount', (select count(*) from "public"."memberships" pm where pm."organization_id" = x."tenant_id")) as j, jsonb_build_array((x."title")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."compliance_policies" x
      where x."tenant_id" = page_compliance_policies.tenant
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."title" ilike v_search or x."key" ilike v_search)
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'requiresAcknowledgement' is not null and jsonb_typeof(v_filters -> 'requiresAcknowledgement') <> 'null' and not (jsonb_typeof(v_filters -> 'requiresAcknowledgement') = 'array' and jsonb_array_length(v_filters -> 'requiresAcknowledgement') = 0)) or x."requires_acknowledgement"::text = any((case when jsonb_typeof(v_filters -> 'requiresAcknowledgement') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'requiresAcknowledgement')) else array[v_filters ->> 'requiresAcknowledgement'] end)::text[]))
        and (v_after is null or (x."title", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."title" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMPLIANCE_POLICY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'ownerId', x."owner_id", 'requiresAcknowledgement', x."requires_acknowledgement", 'versionId', x."current_version_id", 'versionNumber', x."version_number", 'publishedAt', x."published_at", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."acknowledgements" ack where ack."subject_type" = 'compliance_policy' and ack."subject_id" = x."id"::text and ack."version_id" = x."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."acknowledgements" ack join "public"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."subject_type" = 'compliance_policy' and ack."subject_id" = x."id"::text and ack."version_id" = x."current_version_id"), 'memberCount', (select count(*) from "public"."memberships" pm where pm."organization_id" = x."tenant_id")) as j, jsonb_build_array((x."title")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."compliance_policies" x
      where x."tenant_id" = page_compliance_policies.tenant
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."title" ilike v_search or x."key" ilike v_search)
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'requiresAcknowledgement' is not null and jsonb_typeof(v_filters -> 'requiresAcknowledgement') <> 'null' and not (jsonb_typeof(v_filters -> 'requiresAcknowledgement') = 'array' and jsonb_array_length(v_filters -> 'requiresAcknowledgement') = 0)) or x."requires_acknowledgement"::text = any((case when jsonb_typeof(v_filters -> 'requiresAcknowledgement') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'requiresAcknowledgement')) else array[v_filters ->> 'requiresAcknowledgement'] end)::text[]))
        and (v_after is null or (x."title" <= (v_after ->> 0)::text and ((x."title" < (v_after ->> 0)::text) or (x."title" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."title" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMPLIANCE_POLICY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'ownerId', x."owner_id", 'requiresAcknowledgement', x."requires_acknowledgement", 'versionId', x."current_version_id", 'versionNumber', x."version_number", 'publishedAt', x."published_at", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."acknowledgements" ack where ack."subject_type" = 'compliance_policy' and ack."subject_id" = x."id"::text and ack."version_id" = x."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."acknowledgements" ack join "public"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."subject_type" = 'compliance_policy' and ack."subject_id" = x."id"::text and ack."version_id" = x."current_version_id"), 'memberCount', (select count(*) from "public"."memberships" pm where pm."organization_id" = x."tenant_id")) as j, jsonb_build_array((x."title")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."compliance_policies" x
      where x."tenant_id" = page_compliance_policies.tenant
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."title" ilike v_search or x."key" ilike v_search)
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'requiresAcknowledgement' is not null and jsonb_typeof(v_filters -> 'requiresAcknowledgement') <> 'null' and not (jsonb_typeof(v_filters -> 'requiresAcknowledgement') = 'array' and jsonb_array_length(v_filters -> 'requiresAcknowledgement') = 0)) or x."requires_acknowledgement"::text = any((case when jsonb_typeof(v_filters -> 'requiresAcknowledgement') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'requiresAcknowledgement')) else array[v_filters ->> 'requiresAcknowledgement'] end)::text[]))
        and (v_after is null or (x."title", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."title" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMPLIANCE_POLICY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'ownerId', x."owner_id", 'requiresAcknowledgement', x."requires_acknowledgement", 'versionId', x."current_version_id", 'versionNumber', x."version_number", 'publishedAt', x."published_at", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."acknowledgements" ack where ack."subject_type" = 'compliance_policy' and ack."subject_id" = x."id"::text and ack."version_id" = x."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."acknowledgements" ack join "public"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."subject_type" = 'compliance_policy' and ack."subject_id" = x."id"::text and ack."version_id" = x."current_version_id"), 'memberCount', (select count(*) from "public"."memberships" pm where pm."organization_id" = x."tenant_id")) as j, jsonb_build_array((x."title")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."compliance_policies" x
      where x."tenant_id" = page_compliance_policies.tenant
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."title" ilike v_search or x."key" ilike v_search)
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'requiresAcknowledgement' is not null and jsonb_typeof(v_filters -> 'requiresAcknowledgement') <> 'null' and not (jsonb_typeof(v_filters -> 'requiresAcknowledgement') = 'array' and jsonb_array_length(v_filters -> 'requiresAcknowledgement') = 0)) or x."requires_acknowledgement"::text = any((case when jsonb_typeof(v_filters -> 'requiresAcknowledgement') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'requiresAcknowledgement')) else array[v_filters ->> 'requiresAcknowledgement'] end)::text[]))
        and (v_after is null or (x."title" <= (v_after ->> 0)::text and ((x."title" < (v_after ->> 0)::text) or (x."title" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."title" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'publishedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMPLIANCE_POLICY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'ownerId', x."owner_id", 'requiresAcknowledgement', x."requires_acknowledgement", 'versionId', x."current_version_id", 'versionNumber', x."version_number", 'publishedAt', x."published_at", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."acknowledgements" ack where ack."subject_type" = 'compliance_policy' and ack."subject_id" = x."id"::text and ack."version_id" = x."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."acknowledgements" ack join "public"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."subject_type" = 'compliance_policy' and ack."subject_id" = x."id"::text and ack."version_id" = x."current_version_id"), 'memberCount', (select count(*) from "public"."memberships" pm where pm."organization_id" = x."tenant_id")) as j, jsonb_build_array((coalesce(x."published_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."compliance_policies" x
      where x."tenant_id" = page_compliance_policies.tenant
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."title" ilike v_search or x."key" ilike v_search)
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'requiresAcknowledgement' is not null and jsonb_typeof(v_filters -> 'requiresAcknowledgement') <> 'null' and not (jsonb_typeof(v_filters -> 'requiresAcknowledgement') = 'array' and jsonb_array_length(v_filters -> 'requiresAcknowledgement') = 0)) or x."requires_acknowledgement"::text = any((case when jsonb_typeof(v_filters -> 'requiresAcknowledgement') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'requiresAcknowledgement')) else array[v_filters ->> 'requiresAcknowledgement'] end)::text[]))
        and (v_after is null or (coalesce(x."published_at", 'infinity'::timestamptz), x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."published_at", 'infinity'::timestamptz) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'publishedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMPLIANCE_POLICY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'ownerId', x."owner_id", 'requiresAcknowledgement', x."requires_acknowledgement", 'versionId', x."current_version_id", 'versionNumber', x."version_number", 'publishedAt', x."published_at", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."acknowledgements" ack where ack."subject_type" = 'compliance_policy' and ack."subject_id" = x."id"::text and ack."version_id" = x."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."acknowledgements" ack join "public"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."subject_type" = 'compliance_policy' and ack."subject_id" = x."id"::text and ack."version_id" = x."current_version_id"), 'memberCount', (select count(*) from "public"."memberships" pm where pm."organization_id" = x."tenant_id")) as j, jsonb_build_array((coalesce(x."published_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."compliance_policies" x
      where x."tenant_id" = page_compliance_policies.tenant
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."title" ilike v_search or x."key" ilike v_search)
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'requiresAcknowledgement' is not null and jsonb_typeof(v_filters -> 'requiresAcknowledgement') <> 'null' and not (jsonb_typeof(v_filters -> 'requiresAcknowledgement') = 'array' and jsonb_array_length(v_filters -> 'requiresAcknowledgement') = 0)) or x."requires_acknowledgement"::text = any((case when jsonb_typeof(v_filters -> 'requiresAcknowledgement') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'requiresAcknowledgement')) else array[v_filters ->> 'requiresAcknowledgement'] end)::text[]))
        and (v_after is null or (coalesce(x."published_at", 'infinity'::timestamptz) <= (v_after ->> 0)::timestamptz and ((coalesce(x."published_at", 'infinity'::timestamptz) < (v_after ->> 0)::timestamptz) or (coalesce(x."published_at", 'infinity'::timestamptz) = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."published_at", 'infinity'::timestamptz) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."compliance_policies" x
      where x."tenant_id" = page_compliance_policies.tenant
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."title" ilike v_search or x."key" ilike v_search)
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'requiresAcknowledgement' is not null and jsonb_typeof(v_filters -> 'requiresAcknowledgement') <> 'null' and not (jsonb_typeof(v_filters -> 'requiresAcknowledgement') = 'array' and jsonb_array_length(v_filters -> 'requiresAcknowledgement') = 0)) or x."requires_acknowledgement"::text = any((case when jsonb_typeof(v_filters -> 'requiresAcknowledgement') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'requiresAcknowledgement')) else array[v_filters ->> 'requiresAcknowledgement'] end)::text[]))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_compliance_policies"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."page_compliance_policies"(uuid, jsonb) to authenticated, service_role;

-- One policy, or a not-found error. Needs the compliance read permission.
create or replace function "better_supabase"."get_compliance_policy"(policy_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."compliance_policies"%rowtype;
begin
  select * into v_row from "better_supabase"."compliance_policies" x where x."id" = get_compliance_policy.policy_id;
  if not found then
    raise exception 'policy not found' using errcode = 'P0002', hint = 'COMPLIANCE_POLICY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'compliance.read'), false)) then
    raise exception 'not allowed to read policies' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'ownerId', v_row."owner_id", 'requiresAcknowledgement', v_row."requires_acknowledgement", 'versionId', v_row."current_version_id", 'versionNumber', v_row."version_number", 'publishedAt', v_row."published_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."acknowledgements" ack where ack."subject_type" = 'compliance_policy' and ack."subject_id" = v_row."id"::text and ack."version_id" = v_row."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."acknowledgements" ack join "public"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."subject_type" = 'compliance_policy' and ack."subject_id" = v_row."id"::text and ack."version_id" = v_row."current_version_id"), 'memberCount', (select count(*) from "public"."memberships" pm where pm."organization_id" = v_row."tenant_id"));
end;
$$;
revoke execute on function "better_supabase"."get_compliance_policy"(uuid) from public, anon;
grant execute on function "better_supabase"."get_compliance_policy"(uuid) to authenticated, service_role;
-- Imports an OSCAL catalog (1.2.3) as a framework and its controls. The
-- framework key defaults to the catalog uuid. Groups and nested controls
-- flatten into controls by id; the statement prose becomes the description.
-- Importing the same catalog again updates titles and descriptions only.
create or replace function "better_supabase"."import_oscal_catalog"(tenant uuid, document jsonb, key text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid := import_oscal_catalog.tenant;
  v_catalog jsonb;
  v_key text;
  v_title text;
  v_version text;
  v_framework "better_supabase"."control_frameworks"%rowtype;
  v_ctl jsonb;
  v_code text;
  v_ctl_title text;
  v_prose text;
  v_count integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'compliance.manage'), false)) then
    raise exception 'not allowed to manage controls' using errcode = '42501', hint = 'CONTROL_FORBIDDEN';
  end if;
  if import_oscal_catalog.document is null or jsonb_typeof(import_oscal_catalog.document -> 'catalog') is distinct from 'object' then
    raise exception 'the document needs a catalog object' using errcode = '22023', hint = 'OSCAL_INVALID';
  end if;
  v_catalog := import_oscal_catalog.document -> 'catalog';
  v_title := nullif(trim(v_catalog #>> '{metadata,title}'), '');
  if v_title is null then
    raise exception 'the catalog needs a metadata title' using errcode = '22023', hint = 'OSCAL_INVALID';
  end if;
  v_version := nullif(trim(v_catalog #>> '{metadata,version}'), '');
  v_key := coalesce(nullif(trim(import_oscal_catalog.key), ''), 'oscal-' || lower(left(replace(coalesce(v_catalog ->> 'uuid', ''), '-', ''), 12)));
  if v_key !~ '^[a-z0-9][a-z0-9_.-]{0,62}$' then
    raise exception 'key must be lowercase letters, digits, dots, dashes or underscores' using errcode = '22023', hint = 'OSCAL_INVALID';
  end if;
  insert into "better_supabase"."control_frameworks" ("tenant_id", "key", "name", "kind", "version")
  values (v_tenant, v_key, v_title, 'standard', v_version)
  on conflict ("tenant_id", "key") do update set "name" = excluded."name", "version" = excluded."version", "updated_at" = now()
  returning * into v_framework;
  for v_ctl in
    select c from jsonb_path_query(v_catalog, 'strict $.**.controls[*]') c
  loop
    v_code := left(trim(v_ctl ->> 'id'), 50);
    v_ctl_title := left(trim(v_ctl ->> 'title'), 200);
    if v_code is null or v_code = '' or v_ctl_title is null or v_ctl_title = '' then
      raise exception 'every control needs an id and a title' using errcode = '22023', hint = 'OSCAL_INVALID';
    end if;
    v_prose := left(nullif(trim(jsonb_path_query_first(v_ctl, 'lax $.parts[*] ? (@.name == "statement").prose') #>> '{}'), ''), 10000);
    insert into "better_supabase"."controls" ("tenant_id", "framework_id", "code", "title", "description", "source")
    values (v_tenant, v_framework."id", v_code, v_ctl_title, v_prose, 'oscal')
    on conflict ("framework_id", "code") do update set "title" = excluded."title", "description" = excluded."description", "updated_at" = now();
    v_count := v_count + 1;
  end loop;
  perform "better_supabase".emit_event('control_framework.imported', jsonb_build_object('organizationId', v_framework."tenant_id"::text, 'frameworkId', v_framework."id", 'format', 'oscal-catalog', 'controls', v_count), 'controls/' || v_framework."id"::text, (v_framework."tenant_id")::text, null, 'better-supabase/compliance');
  perform better_supabase.audit_event(
    event_type => 'control_framework.imported',
    category => 'data',
    target_type => 'control_framework',
    record_id => v_framework."id"::text,
    tenant => (v_framework."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_framework."tenant_id"::text, 'frameworkId', v_framework."id", 'format', 'oscal-catalog', 'controls', v_count)
  );
  return jsonb_build_object('frameworkId', v_framework."id", 'key', v_framework."key", 'controls', v_count);
end;
$$;
revoke execute on function "better_supabase"."import_oscal_catalog"(uuid, jsonb, text) from public, anon;
grant execute on function "better_supabase"."import_oscal_catalog"(uuid, jsonb, text) to authenticated, service_role;

-- Applies an OSCAL profile to a framework: the controls it includes apply and
-- the others do not (the statement of applicability). A profile includes
-- controls with include-all or include-controls with-ids, minus
-- exclude-controls with-ids, across its imports. Its import href is not
-- followed; the profile applies to the framework you name. Returns the counts
-- and the ids the framework has no control for.
create or replace function "better_supabase"."apply_oscal_profile"(framework_id uuid, document jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_framework "better_supabase"."control_frameworks"%rowtype;
  v_import jsonb;
  v_all boolean := false;
  v_included text[] := '{}';
  v_excluded text[] := '{}';
  v_codes text[];
  v_applicable integer;
  v_other integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_framework from "better_supabase"."control_frameworks" x where x."id" = apply_oscal_profile.framework_id;
  if not found then
    raise exception 'framework not found' using errcode = 'P0002', hint = 'CONTROL_FRAMEWORK_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_framework."tenant_id", 'compliance.manage'), false)) then
    raise exception 'not allowed to manage controls' using errcode = '42501', hint = 'CONTROL_FORBIDDEN';
  end if;
  if apply_oscal_profile.document is null or jsonb_typeof(apply_oscal_profile.document -> 'profile') is distinct from 'object' then
    raise exception 'the document needs a profile object' using errcode = '22023', hint = 'OSCAL_INVALID';
  end if;
  if jsonb_typeof(apply_oscal_profile.document #> '{profile,imports}') is distinct from 'array' then
    raise exception 'the profile needs imports' using errcode = '22023', hint = 'OSCAL_INVALID';
  end if;
  for v_import in select i from jsonb_array_elements(apply_oscal_profile.document #> '{profile,imports}') i loop
    if v_import ? 'include-all' then
      v_all := true;
    end if;
    v_included := v_included || coalesce(array(select jsonb_array_elements_text(jsonb_path_query_array(v_import, 'lax $."include-controls"[*]."with-ids"[*]'))), '{}');
    v_excluded := v_excluded || coalesce(array(select jsonb_array_elements_text(jsonb_path_query_array(v_import, 'lax $."exclude-controls"[*]."with-ids"[*]'))), '{}');
  end loop;
  if not v_all and cardinality(v_included) = 0 then
    raise exception 'the profile includes no controls' using errcode = '22023', hint = 'OSCAL_INVALID';
  end if;
  select coalesce(array_agg(c."code"), '{}') into v_codes from "better_supabase"."controls" c where c."framework_id" = v_framework."id";
  update "better_supabase"."controls" c set "applicable" = (v_all or c."code" = any(v_included)) and not (c."code" = any(v_excluded)), "updated_at" = now()
  where c."framework_id" = v_framework."id"
    and c."applicable" is distinct from ((v_all or c."code" = any(v_included)) and not (c."code" = any(v_excluded)));
  select count(*) filter (where c."applicable"), count(*) filter (where not c."applicable") into v_applicable, v_other
  from "better_supabase"."controls" c where c."framework_id" = v_framework."id";
  return jsonb_build_object(
    'frameworkId', v_framework."id",
    'applicable', v_applicable,
    'notApplicable', v_other,
    'unknownIds', to_jsonb(array(select distinct i from unnest(v_included || v_excluded) i where not (i = any(v_codes)) order by i))
  );
end;
$$;
revoke execute on function "better_supabase"."apply_oscal_profile"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."apply_oscal_profile"(uuid, jsonb) to authenticated, service_role;

-- An OSCAL assessment-results document (1.2.3) for a framework: one
-- result with an observation per piece of evidence and a finding per applicable
-- control, satisfied when the control has evidence that is still valid. The
-- import-ap href is the framework's urn, as no assessment plan exists.
create or replace function "better_supabase"."export_oscal_assessment_results"(framework_id uuid, title text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_framework "better_supabase"."control_frameworks"%rowtype;
  v_now text := to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"');
  v_title text;
begin
  select * into v_framework from "better_supabase"."control_frameworks" x where x."id" = export_oscal_assessment_results.framework_id;
  if not found then
    raise exception 'framework not found' using errcode = 'P0002', hint = 'CONTROL_FRAMEWORK_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_framework."tenant_id", 'compliance.read'), false)) then
    raise exception 'not allowed to read controls' using errcode = '42501', hint = 'CONTROL_FORBIDDEN';
  end if;
  v_title := coalesce(nullif(trim(export_oscal_assessment_results.title), ''), v_framework."name" || ' assessment results');
  return jsonb_build_object('assessment-results', jsonb_build_object(
    'uuid', gen_random_uuid(),
    'metadata', jsonb_build_object(
      'title', v_title,
      'last-modified', v_now,
      'version', coalesce(v_framework."version", '1'),
      'oscal-version', '1.2.3'
    ),
    'import-ap', jsonb_build_object('href', 'urn:uuid:' || v_framework."id"::text),
    'results', jsonb_build_array(jsonb_build_object(
      'uuid', gen_random_uuid(),
      'title', v_title,
      'description', 'Evidence collected for the applicable controls of ' || v_framework."name" || '.',
      'start', v_now,
      'reviewed-controls', jsonb_build_object('control-selections', jsonb_build_array(jsonb_build_object(
        'include-controls', coalesce((
          select jsonb_agg(jsonb_build_object('control-id', c."code") order by c."code")
          from "better_supabase"."controls" c where c."framework_id" = v_framework."id" and c."applicable"
        ), '[]'::jsonb)
      ))),
      'observations', coalesce((
        select jsonb_agg(jsonb_build_object(
          'uuid', ev."id",
          'description', coalesce(ev."note", 'Evidence for control ' || c."code"),
          'methods', jsonb_build_array('EXAMINE'),
          'collected', to_char(ev."collected_at" at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
          'relevant-evidence', jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
            'description', coalesce(ev."note", 'Attachment'),
            'href', case when ev."attachment_id" is null then null else 'urn:uuid:' || ev."attachment_id"::text end
          )))
        ) order by c."code", ev."collected_at", ev."id")
        from "better_supabase"."control_evidence" ev
        join "better_supabase"."controls" c on c."id" = ev."control_id"
        where c."framework_id" = v_framework."id" and c."applicable"
      ), '[]'::jsonb),
      'findings', coalesce((
        select jsonb_agg(jsonb_build_object(
          'uuid', gen_random_uuid(),
          'title', c."code" || ' ' || c."title",
          'description', c."title",
          'target', jsonb_build_object(
            'type', 'objective-id',
            'target-id', c."code",
            'status', jsonb_build_object('state', case when exists (
              select 1 from "better_supabase"."control_evidence" ev where ev."control_id" = c."id" and (ev."valid_until" is null or ev."valid_until" >= current_date)
            ) then 'satisfied' else 'not-satisfied' end)
          ),
          'related-observations', coalesce((
            select jsonb_agg(jsonb_build_object('observation-uuid', ev."id") order by ev."collected_at", ev."id")
            from "better_supabase"."control_evidence" ev where ev."control_id" = c."id"
          ), '[]'::jsonb)
        ) order by c."code")
        from "better_supabase"."controls" c where c."framework_id" = v_framework."id" and c."applicable"
      ), '[]'::jsonb)
    ))
  ));
end;
$$;
revoke execute on function "better_supabase"."export_oscal_assessment_results"(uuid, text) from public, anon;
grant execute on function "better_supabase"."export_oscal_assessment_results"(uuid, text) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."control_frameworks" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."control_frameworks" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."control_frameworks" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."control_frameworks" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."controls" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."controls" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."controls" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."controls" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."control_evidence" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."control_evidence" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."control_evidence" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."control_evidence" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."evidence_tasks" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("assignee_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."evidence_tasks" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."evidence_tasks" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."evidence_tasks" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."compliance_policies" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('compliance.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."compliance_policies" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."compliance_policies" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."compliance_policies" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create trigger "bsb_search_control_index"
  after insert or delete on "better_supabase"."controls"
  for each row execute function "better_supabase"."search_index_row"('control', 'id');
create trigger "bsb_search_control_index_u"
  after update of "id", "tenant_id", "title" on "better_supabase"."controls"
  for each row when (old."id" is distinct from new."id" or old."tenant_id" is distinct from new."tenant_id" or old."title" is distinct from new."title")
  execute function "better_supabase"."search_index_row"('control', 'id');
create trigger "bsb_search_compliance_policy_index"
  after insert or delete on "better_supabase"."compliance_policies"
  for each row execute function "better_supabase"."search_index_row"('compliance_policy', 'id');
create trigger "bsb_search_compliance_policy_index_u"
  after update of "id", "tenant_id", "title", "key" on "better_supabase"."compliance_policies"
  for each row when (old."id" is distinct from new."id" or old."tenant_id" is distinct from new."tenant_id" or old."title" is distinct from new."title" or old."key" is distinct from new."key")
  execute function "better_supabase"."search_index_row"('compliance_policy', 'id');

-- Row audit for the module's tables (blocks.audit.options.blockTables)
create constraint trigger bsb_audit after insert or update or delete on better_supabase.controls deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"control","event_prefix":"control"}');
create constraint trigger bsb_audit after insert or update or delete on better_supabase.control_frameworks deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"control_framework","event_prefix":"control_framework"}');
create constraint trigger bsb_audit after insert or update or delete on better_supabase.evidence_tasks deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"evidence_task","event_prefix":"evidence_task"}');
create constraint trigger bsb_audit after insert or update or delete on better_supabase.compliance_policies deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"compliance_policy","event_prefix":"compliance_policy","archive_column":"archived_at"}');

-- blocks.compliance.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."save_control_framework"(tenant uuid, key text, name text, version text default null, description text default null, kind text default 'standard')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_control_framework"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."save_control_framework"(uuid, text, text, text, text, text) from public, anon;
grant execute on function "api"."save_control_framework"(uuid, text, text, text, text, text) to authenticated, service_role;

create or replace function "api"."list_control_frameworks"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_control_frameworks"($1) $$;
revoke execute on function "api"."list_control_frameworks"(uuid) from public, anon;
grant execute on function "api"."list_control_frameworks"(uuid) to authenticated, service_role;

create or replace function "api"."page_control_frameworks"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."page_control_frameworks"($1, $2) $$;
revoke execute on function "api"."page_control_frameworks"(uuid, jsonb) from public, anon;
grant execute on function "api"."page_control_frameworks"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."get_control_framework"(framework_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."get_control_framework"($1) $$;
revoke execute on function "api"."get_control_framework"(uuid) from public, anon;
grant execute on function "api"."get_control_framework"(uuid) to authenticated, service_role;

create or replace function "api"."save_control"(framework_id uuid, code text, title text, description text default null, owner_id uuid default null, applicable boolean default true, control_id uuid default null, source text default null, jurisdiction text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_control"($1, $2, $3, $4, $5, $6, $7, $8, $9) $$;
revoke execute on function "api"."save_control"(uuid, text, text, text, uuid, boolean, uuid, text, text) from public, anon;
grant execute on function "api"."save_control"(uuid, text, text, text, uuid, boolean, uuid, text, text) to authenticated, service_role;

create or replace function "api"."get_control"(control_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."get_control"($1) $$;
revoke execute on function "api"."get_control"(uuid) from public, anon;
grant execute on function "api"."get_control"(uuid) to authenticated, service_role;

create or replace function "api"."list_controls"(tenant uuid, framework_id uuid default null, status text default null, owner_id uuid default null, page_size integer default 200)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_controls"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."list_controls"(uuid, uuid, text, uuid, integer) from public, anon;
grant execute on function "api"."list_controls"(uuid, uuid, text, uuid, integer) to authenticated, service_role;

create or replace function "api"."add_control_evidence"(control_id uuid, attachment_id uuid default null, note text default null, valid_until date default null, task_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."add_control_evidence"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."add_control_evidence"(uuid, uuid, text, date, uuid) from public, anon;
grant execute on function "api"."add_control_evidence"(uuid, uuid, text, date, uuid) to authenticated, service_role;

create or replace function "api"."remove_control_evidence"(evidence_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."remove_control_evidence"($1) $$;
revoke execute on function "api"."remove_control_evidence"(uuid) from public, anon;
grant execute on function "api"."remove_control_evidence"(uuid) to authenticated, service_role;

create or replace function "api"."save_evidence_task"(control_id uuid, title text, interval_days integer, due_on date default null, assignee_id uuid default null, active boolean default true, task_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_evidence_task"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."save_evidence_task"(uuid, text, integer, date, uuid, boolean, uuid) from public, anon;
grant execute on function "api"."save_evidence_task"(uuid, text, integer, date, uuid, boolean, uuid) to authenticated, service_role;

create or replace function "api"."list_evidence_tasks"(tenant uuid, control_id uuid default null, assignee_id uuid default null, overdue_only boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_evidence_tasks"($1, $2, $3, $4) $$;
revoke execute on function "api"."list_evidence_tasks"(uuid, uuid, uuid, boolean) from public, anon;
grant execute on function "api"."list_evidence_tasks"(uuid, uuid, uuid, boolean) to authenticated, service_role;

create or replace function "api"."page_evidence_tasks"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."page_evidence_tasks"($1, $2) $$;
revoke execute on function "api"."page_evidence_tasks"(uuid, jsonb) from public, anon;
grant execute on function "api"."page_evidence_tasks"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."get_evidence_task"(task_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."get_evidence_task"($1) $$;
revoke execute on function "api"."get_evidence_task"(uuid) from public, anon;
grant execute on function "api"."get_evidence_task"(uuid) to authenticated, service_role;

create or replace function "api"."control_posture"(tenant uuid, framework_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."control_posture"($1, $2) $$;
revoke execute on function "api"."control_posture"(uuid, uuid) from public, anon;
grant execute on function "api"."control_posture"(uuid, uuid) to authenticated, service_role;

create or replace function "api"."notify_overdue_evidence_tasks"()
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."notify_overdue_evidence_tasks"() $$;
revoke execute on function "api"."notify_overdue_evidence_tasks"() from public, anon, authenticated;
grant execute on function "api"."notify_overdue_evidence_tasks"() to service_role;

create or replace function "api"."save_compliance_policy"(tenant uuid, key text, title text, owner_id uuid default null, requires_acknowledgement boolean default true, policy_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_compliance_policy"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."save_compliance_policy"(uuid, text, text, uuid, boolean, uuid) from public, anon;
grant execute on function "api"."save_compliance_policy"(uuid, text, text, uuid, boolean, uuid) to authenticated, service_role;

create or replace function "api"."publish_compliance_policy"(policy_id uuid, content jsonb, label text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."publish_compliance_policy"($1, $2, $3) $$;
revoke execute on function "api"."publish_compliance_policy"(uuid, jsonb, text) from public, anon;
grant execute on function "api"."publish_compliance_policy"(uuid, jsonb, text) to authenticated, service_role;

create or replace function "api"."archive_compliance_policy"(policy_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."archive_compliance_policy"($1) $$;
revoke execute on function "api"."archive_compliance_policy"(uuid) from public, anon;
grant execute on function "api"."archive_compliance_policy"(uuid) to authenticated, service_role;

create or replace function "api"."restore_compliance_policy"(policy_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."restore_compliance_policy"($1) $$;
revoke execute on function "api"."restore_compliance_policy"(uuid) from public, anon;
grant execute on function "api"."restore_compliance_policy"(uuid) to authenticated, service_role;

create or replace function "api"."list_compliance_policies"(tenant uuid, include_archived boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_compliance_policies"($1, $2) $$;
revoke execute on function "api"."list_compliance_policies"(uuid, boolean) from public, anon;
grant execute on function "api"."list_compliance_policies"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."page_compliance_policies"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."page_compliance_policies"($1, $2) $$;
revoke execute on function "api"."page_compliance_policies"(uuid, jsonb) from public, anon;
grant execute on function "api"."page_compliance_policies"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."get_compliance_policy"(policy_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."get_compliance_policy"($1) $$;
revoke execute on function "api"."get_compliance_policy"(uuid) from public, anon;
grant execute on function "api"."get_compliance_policy"(uuid) to authenticated, service_role;

create or replace function "api"."import_oscal_catalog"(tenant uuid, document jsonb, key text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."import_oscal_catalog"($1, $2, $3) $$;
revoke execute on function "api"."import_oscal_catalog"(uuid, jsonb, text) from public, anon;
grant execute on function "api"."import_oscal_catalog"(uuid, jsonb, text) to authenticated, service_role;

create or replace function "api"."apply_oscal_profile"(framework_id uuid, document jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."apply_oscal_profile"($1, $2) $$;
revoke execute on function "api"."apply_oscal_profile"(uuid, jsonb) from public, anon;
grant execute on function "api"."apply_oscal_profile"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."export_oscal_assessment_results"(framework_id uuid, title text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."export_oscal_assessment_results"($1, $2) $$;
revoke execute on function "api"."export_oscal_assessment_results"(uuid, text) from public, anon;
grant execute on function "api"."export_oscal_assessment_results"(uuid, text) to authenticated, service_role;
