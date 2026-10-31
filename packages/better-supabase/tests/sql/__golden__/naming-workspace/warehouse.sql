-- ==== schema supabase/schemas/900_better_supabase_166_warehouse.sql
-- better-supabase module: warehouse
-- @bsb-block warehouse@1 managed
-- @bsb-hash sha256:39dbec29a1b177a7f05c288a27b8fb813c94ca97b39c7767b1ab7f5a5a4ce571
-- Warehouse work over inventory: pick waves and pick lists made from stock allocations, picking tasks as work items, confirmed bins, lots and serials, and cycle count plans that hold large variances for review.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."pick_waves";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."pick_waves";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pick_waves";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."pick_waves";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pick_waves";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."pick_lists";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."pick_lists";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pick_lists";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."pick_lists";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pick_lists";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."pick_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."pick_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pick_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."pick_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pick_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."count_plans";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."count_plans";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."count_plans";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."count_plans";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."count_plans";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Warehouse work over the inventory block: waves of pick lists made from a
-- document's stock allocations, each a work item for a picker, with the bin,
-- lot and serial numbers the picker confirms, and cycle count plans that open
-- the inventory block's stock counts on a schedule and hold large variances for
-- a review before they post.

-- A wave groups pick lists that are picked together.
create table if not exists "better_supabase"."pick_waves" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 200),
  "location_id" uuid not null references "better_supabase"."inventory_locations" ("id") on delete cascade,
  "status" text not null default 'draft' check ("status" in ('draft', 'released', 'completed', 'cancelled')),
  "released_at" timestamptz,
  "completed_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "id")
);
create index if not exists "pick_waves_tenant_idx" on "better_supabase"."pick_waves" ("tenant_id", "status", "created_at" desc);
create index if not exists "pick_waves_location_idx" on "better_supabase"."pick_waves" ("location_id");
alter table "better_supabase"."pick_waves" enable row level security;
revoke all on "better_supabase"."pick_waves" from public, anon, authenticated;
grant select on "better_supabase"."pick_waves" to authenticated;
grant all on "better_supabase"."pick_waves" to service_role;
drop policy if exists pick_waves_read on "better_supabase"."pick_waves";
create policy pick_waves_read on "better_supabase"."pick_waves"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('warehouse.read')));

-- One document's stock to pick at one location, as a work item for a picker.
create table if not exists "better_supabase"."pick_lists" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "wave_id" uuid,
  "location_id" uuid not null references "better_supabase"."inventory_locations" ("id") on delete cascade,
  "document_type" text not null check ("document_type" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "document_id" text not null check (length("document_id") between 1 and 200),
  "status" text not null default 'open' check ("status" in ('open', 'picked', 'cancelled')),
  "assignee_id" uuid,
  -- The tasks block's work item for the picker, when it is installed.
  "task_id" uuid,
  "picked_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "id"),
  foreign key ("tenant_id", "wave_id") references "better_supabase"."pick_waves" ("tenant_id", "id") on delete cascade,
  check (("status" = 'picked') = ("picked_at" is not null))
);
create index if not exists "pick_lists_wave_idx" on "better_supabase"."pick_lists" ("tenant_id", "wave_id");
create index if not exists "pick_lists_document_idx" on "better_supabase"."pick_lists" ("tenant_id", "document_type", "document_id");
create index if not exists "pick_lists_assignee_idx" on "better_supabase"."pick_lists" ("tenant_id", "assignee_id", "status");
create index if not exists "pick_lists_location_idx" on "better_supabase"."pick_lists" ("location_id");
alter table "better_supabase"."pick_lists" enable row level security;
revoke all on "better_supabase"."pick_lists" from public, anon, authenticated;
grant select on "better_supabase"."pick_lists" to authenticated;
grant all on "better_supabase"."pick_lists" to service_role;
drop policy if exists pick_lists_read on "better_supabase"."pick_lists";
create policy pick_lists_read on "better_supabase"."pick_lists"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('warehouse.read')));

-- One allocation to pick. bin_id and lot_id are where to find the stock, set
-- from the stock levels when the line is made and by the picker when picked.
create table if not exists "better_supabase"."pick_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "pick_list_id" uuid not null,
  "allocation_id" uuid not null references "better_supabase"."stock_allocations" ("id") on delete cascade,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "bin_id" uuid,
  "lot_id" uuid,
  "serials" text[],
  "quantity" numeric(20, 6) not null check ("quantity" > 0),
  "picked" numeric(20, 6) not null default 0 check ("picked" >= 0 and "picked" <= "quantity"),
  "status" text not null default 'open' check ("status" in ('open', 'picked', 'short', 'cancelled')),
  "picked_at" timestamptz,
  "picked_by" uuid,
  foreign key ("tenant_id", "pick_list_id") references "better_supabase"."pick_lists" ("tenant_id", "id") on delete cascade
);
create index if not exists "pick_lines_parent_idx" on "better_supabase"."pick_lines" ("tenant_id", "pick_list_id");
create index if not exists "pick_lines_allocation_idx" on "better_supabase"."pick_lines" ("allocation_id");
create index if not exists "pick_lines_variant_idx" on "better_supabase"."pick_lines" ("variant_id");
-- An allocation is on one open pick line at a time.
create unique index if not exists "pick_lines_open_key" on "better_supabase"."pick_lines" ("allocation_id") where "status" = 'open';
alter table "better_supabase"."pick_lines" enable row level security;
revoke all on "better_supabase"."pick_lines" from public, anon, authenticated;
grant select on "better_supabase"."pick_lines" to authenticated;
grant all on "better_supabase"."pick_lines" to service_role;
drop policy if exists pick_lines_read on "better_supabase"."pick_lines";
create policy pick_lines_read on "better_supabase"."pick_lines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('warehouse.read')));

-- A cycle count schedule: every_days days a count of the location opens, of
-- all its stock or of variant_ids only. A posted count whose variance stays
-- under variance_limit_pct of what the books held posts without a review.
create table if not exists "better_supabase"."count_plans" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 200),
  "location_id" uuid not null references "better_supabase"."inventory_locations" ("id") on delete cascade,
  "every_days" integer not null check ("every_days" between 1 and 3660),
  "variant_ids" uuid[],
  "variance_limit_pct" numeric(6, 2) not null default 5 check ("variance_limit_pct" >= 0),
  "next_run_on" date not null default current_date,
  "last_run_at" timestamptz,
  "last_count_id" uuid,
  "active" boolean not null default true,
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "id")
);
create index if not exists "count_plans_due_idx" on "better_supabase"."count_plans" ("tenant_id", "next_run_on") where "active";
create index if not exists "count_plans_location_idx" on "better_supabase"."count_plans" ("location_id");
alter table "better_supabase"."count_plans" enable row level security;
revoke all on "better_supabase"."count_plans" from public, anon, authenticated;
grant select on "better_supabase"."count_plans" to authenticated;
grant all on "better_supabase"."count_plans" to service_role;
drop policy if exists count_plans_read on "better_supabase"."count_plans";
create policy count_plans_read on "better_supabase"."count_plans"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('warehouse.read')));


-- The pick list as json, with its lines.
create or replace function "better_supabase"."pick_list_json"(pick_list_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'waveId', x."wave_id",
    'locationId', x."location_id", 'documentType', x."document_type", 'documentId', x."document_id",
    'status', x."status", 'assigneeId', x."assignee_id", 'taskId', x."task_id",
    'pickedAt', x."picked_at", 'createdAt', x."created_at",
    'lines', coalesce((
      select jsonb_agg(jsonb_build_object('id', y."id", 'allocationId', y."allocation_id", 'variantId', y."variant_id",
        'binId', y."bin_id", 'lotId', y."lot_id", 'serials', to_jsonb(y."serials"),
        'quantity', y."quantity"::text, 'picked', y."picked"::text, 'status', y."status",
        'pickedAt', y."picked_at", 'pickedBy', y."picked_by")
        order by y."variant_id", y."id")
      from "better_supabase"."pick_lines" y where y."pick_list_id" = x."id"
    ), '[]'::jsonb))
  from "better_supabase"."pick_lists" x where x."id" = pick_list_json.pick_list_id
$$;
revoke execute on function "better_supabase"."pick_list_json"(uuid) from public, anon, authenticated;

-- The tasks block isn't installed, so a pick list has no work item.
create or replace function "better_supabase"."pick_list_task"(pick_list_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  return;
end;
$$;
revoke execute on function "better_supabase"."pick_list_task"(uuid) from public, anon, authenticated;

-- Creates a draft pick wave for a location. input is { name, locationId }.
-- Needs warehouse.manage.
create or replace function "better_supabase"."create_pick_wave"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."pick_waves";
  v_name text;
  v_location uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_pick_wave.tenant is not null and coalesce(better_supabase.can('tenant', create_pick_wave.tenant, 'warehouse.manage'), false))) then
    raise exception 'not allowed to manage pick waves' using errcode = '42501', hint = 'WAREHOUSE_FORBIDDEN';
  end if;
  if jsonb_typeof(create_pick_wave.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  begin
    v_name := trim(create_pick_wave.input ->> 'name');
    v_location := (create_pick_wave.input ->> 'locationId')::uuid;
  exception when invalid_text_representation then
    raise exception 'locationId is a uuid' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end;
  if coalesce(length(v_name), 0) not between 1 and 200 then
    raise exception 'a wave needs a name of 1 to 200 characters' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  if not exists (select 1 from "better_supabase"."inventory_locations" x where x."id" = v_location and x."tenant_id" = create_pick_wave.tenant) then
    raise exception 'no such location in this organization' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  insert into "better_supabase"."pick_waves" ("tenant_id", "name", "location_id", "created_by")
  values (create_pick_wave.tenant, v_name, v_location, auth.uid())
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'locationId', v_row."location_id", 'status', v_row."status", 'releasedAt', v_row."released_at", 'completedAt', v_row."completed_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."create_pick_wave"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."create_pick_wave"(uuid, jsonb) to authenticated, service_role;

-- Makes a pick list from the open allocations of a document at a location.
-- input is { locationId, documentType, documentId, waveId, assigneeId }. A line
-- is made for each allocation that holds stock and is on no open pick line, and
-- starts with the bin and lot that hold the most of the variant. A list in a
-- draft wave waits for the wave's release; a list without a wave gets its work
-- item now. Needs warehouse.manage.
create or replace function "better_supabase"."create_pick_list"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."pick_lists";
  v_wave "better_supabase"."pick_waves";
  v_location uuid;
  v_type text;
  v_document text;
  v_wave_id uuid;
  v_assignee uuid;
  v_lines integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_pick_list.tenant is not null and coalesce(better_supabase.can('tenant', create_pick_list.tenant, 'warehouse.manage'), false))) then
    raise exception 'not allowed to manage pick lists' using errcode = '42501', hint = 'WAREHOUSE_FORBIDDEN';
  end if;
  if jsonb_typeof(create_pick_list.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  begin
    v_location := (create_pick_list.input ->> 'locationId')::uuid;
    v_type := trim(create_pick_list.input ->> 'documentType');
    v_document := trim(create_pick_list.input ->> 'documentId');
    v_wave_id := nullif(create_pick_list.input ->> 'waveId', '')::uuid;
    v_assignee := nullif(create_pick_list.input ->> 'assigneeId', '')::uuid;
  exception when invalid_text_representation then
    raise exception 'locationId, waveId and assigneeId are uuids' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end;
  if v_type is null or v_type !~ '^[a-z][a-z0-9_]{0,62}$' or coalesce(length(v_document), 0) not between 1 and 200 then
    raise exception 'a pick list needs a documentType in snake_case and a documentId' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  if not exists (select 1 from "better_supabase"."inventory_locations" x where x."id" = v_location and x."tenant_id" = create_pick_list.tenant) then
    raise exception 'no such location in this organization' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  if v_wave_id is not null then
    select * into v_wave from "better_supabase"."pick_waves" x
    where x."id" = v_wave_id and x."tenant_id" = create_pick_list.tenant for update;
    if not found then
      raise exception 'no such pick wave' using errcode = 'P0002', hint = 'WAREHOUSE_WAVE_NOT_FOUND';
    end if;
    if v_wave."status" <> 'draft' or v_wave."location_id" <> v_location then
      raise exception 'a list joins a draft wave of the same location' using errcode = '55000', hint = 'WAREHOUSE_STATE';
    end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_pick_list_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using create_pick_list.tenant, create_pick_list.input;
    end if;
  end;
  insert into "better_supabase"."pick_lists" ("tenant_id", "wave_id", "location_id", "document_type", "document_id", "assignee_id", "created_by")
  values (create_pick_list.tenant, v_wave_id, v_location, v_type, v_document, v_assignee, auth.uid())
  returning * into v_row;
  insert into "better_supabase"."pick_lines" ("tenant_id", "pick_list_id", "allocation_id", "variant_id", "bin_id", "lot_id", "quantity")
  select v_row."tenant_id", v_row."id", x."id", x."variant_id", b.bin, b.lot, x."allocated"
  from "better_supabase"."stock_allocations" x
  left join lateral (
    select y."bin_id" as bin, y."lot_id" as lot
    from "better_supabase"."stock_buckets" y
    where y."variant_id" = x."variant_id" and y."location_id" = x."location_id" and y."on_hand" > 0
    order by y."on_hand" desc, y."lot_id" nulls last, y."bin_id" nulls last
    limit 1
  ) b on true
  where x."tenant_id" = v_row."tenant_id" and x."location_id" = v_location
    and x."document_type" = v_type and x."document_id" = v_document
    and x."status" = 'open' and x."allocated" > 0
    and not exists (select 1 from "better_supabase"."pick_lines" z where z."allocation_id" = x."id" and z."status" = 'open');
  get diagnostics v_lines = row_count;
  if v_lines = 0 then
    raise exception 'the document has no allocated stock left to pick at this location' using errcode = '55000', hint = 'WAREHOUSE_STATE';
  end if;
  if v_row."wave_id" is null then
    perform "better_supabase"."pick_list_task"(v_row."id");
  end if;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_pick_list_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return "better_supabase"."pick_list_json"(v_row."id");
end;
$$;
revoke execute on function "better_supabase"."create_pick_list"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."create_pick_list"(uuid, jsonb) to authenticated, service_role;

-- Releases a draft wave: its pick lists become work items for the pickers and
-- can be picked. Needs warehouse.manage.
create or replace function "better_supabase"."release_pick_wave"(wave_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."pick_waves";
  v_list uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."pick_waves" x where x."id" = release_pick_wave.wave_id for update;
  if not found then
    raise exception 'no such pick wave' using errcode = 'P0002', hint = 'WAREHOUSE_WAVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'warehouse.manage'), false))) then
    raise exception 'not allowed to manage pick waves' using errcode = '42501', hint = 'WAREHOUSE_FORBIDDEN';
  end if;
  if v_row."status" <> 'draft' then
    raise exception 'only a draft wave is released' using errcode = '55000', hint = 'WAREHOUSE_STATE';
  end if;
  if not exists (select 1 from "better_supabase"."pick_lists" x where x."wave_id" = v_row."id" and x."status" = 'open') then
    raise exception 'a wave needs a pick list before it is released' using errcode = '55000', hint = 'WAREHOUSE_STATE';
  end if;
  for v_list in select x."id" from "better_supabase"."pick_lists" x where x."wave_id" = v_row."id" and x."status" = 'open' order by x."created_at", x."id" loop
    perform "better_supabase"."pick_list_task"(v_list);
  end loop;
  update "better_supabase"."pick_waves" x set "status" = 'released', "released_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'locationId', v_row."location_id", 'status', v_row."status", 'releasedAt', v_row."released_at", 'completedAt', v_row."completed_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."release_pick_wave"(uuid) from public, anon;
grant execute on function "better_supabase"."release_pick_wave"(uuid) to authenticated, service_role;

-- Cancels a draft or released wave with its open pick lists and lines. What
-- was picked stays recorded on the lines. Needs warehouse.manage.
create or replace function "better_supabase"."cancel_pick_wave"(wave_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."pick_waves";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."pick_waves" x where x."id" = cancel_pick_wave.wave_id for update;
  if not found then
    raise exception 'no such pick wave' using errcode = 'P0002', hint = 'WAREHOUSE_WAVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'warehouse.manage'), false))) then
    raise exception 'not allowed to manage pick waves' using errcode = '42501', hint = 'WAREHOUSE_FORBIDDEN';
  end if;
  if v_row."status" not in ('draft', 'released') then
    raise exception 'only a draft or released wave is cancelled' using errcode = '55000', hint = 'WAREHOUSE_STATE';
  end if;
  update "better_supabase"."pick_lines" y set "status" = 'cancelled'
  from "better_supabase"."pick_lists" x
  where y."pick_list_id" = x."id" and x."wave_id" = v_row."id" and x."status" = 'open' and y."status" = 'open';
  update "better_supabase"."pick_lists" x set "status" = 'cancelled' where x."wave_id" = v_row."id" and x."status" = 'open';
  update "better_supabase"."pick_waves" x set "status" = 'cancelled' where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'locationId', v_row."location_id", 'status', v_row."status", 'releasedAt', v_row."released_at", 'completedAt', v_row."completed_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."cancel_pick_wave"(uuid) from public, anon;
grant execute on function "better_supabase"."cancel_pick_wave"(uuid) to authenticated, service_role;

-- Records what a picker found for a line of an open pick list. attrs is
-- { quantity, binId, lotId, serials }: quantity is added to what was picked,
-- and the bin, lot and serial numbers replace the suggestion when given. A line
-- is picked once its quantity is. The stock stays where it is until the
-- document ships. Needs warehouse.pick on a list assigned to the caller or to
-- nobody, or warehouse.manage.
create or replace function "better_supabase"."record_pick"(line_id uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_line "better_supabase"."pick_lines";
  v_list "better_supabase"."pick_lists";
  v_wave_status text;
  v_quantity numeric;
  v_bin uuid;
  v_lot uuid;
  v_serials text[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_line from "better_supabase"."pick_lines" x where x."id" = record_pick.line_id for update;
  if not found then
    raise exception 'no such pick line' using errcode = 'P0002', hint = 'WAREHOUSE_PICK_LINE_NOT_FOUND';
  end if;
  select * into v_list from "better_supabase"."pick_lists" x where x."id" = v_line."pick_list_id";
  if not coalesce(((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_list."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_list."tenant_id", 'warehouse.manage'), false))) or ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_list."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_list."tenant_id", 'warehouse.pick'), false))) and coalesce(v_list."assignee_id" is null or v_list."assignee_id" = auth.uid(), false))), false) then
    raise exception 'not allowed to pick from this list' using errcode = '42501', hint = 'WAREHOUSE_FORBIDDEN';
  end if;
  if jsonb_typeof(record_pick.attrs) is distinct from 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  begin
    v_quantity := (record_pick.attrs ->> 'quantity')::numeric;
    v_bin := nullif(record_pick.attrs ->> 'binId', '')::uuid;
    v_lot := nullif(record_pick.attrs ->> 'lotId', '')::uuid;
    if jsonb_typeof(record_pick.attrs -> 'serials') = 'array' then
      v_serials := array(select jsonb_array_elements_text(record_pick.attrs -> 'serials'));
    end if;
  exception when invalid_text_representation then
    raise exception 'quantity is a number and binId and lotId are uuids' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end;
  if v_list."status" <> 'open' or v_line."status" <> 'open' then
    raise exception 'the pick list or the line is no longer open' using errcode = '55000', hint = 'WAREHOUSE_STATE';
  end if;
  if v_list."wave_id" is not null then
    select x."status" into v_wave_status from "better_supabase"."pick_waves" x where x."id" = v_list."wave_id";
    if v_wave_status <> 'released' then
      raise exception 'the wave isn''t released yet' using errcode = '55000', hint = 'WAREHOUSE_STATE';
    end if;
  end if;
  if v_quantity is null or v_quantity <= 0 or v_quantity > v_line."quantity" - v_line."picked" then
    raise exception 'the quantity must be more than zero and at most what is left to pick' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  if v_bin is not null and not exists (select 1 from "better_supabase"."stock_bins" x where x."id" = v_bin and x."tenant_id" = v_line."tenant_id") then
    raise exception 'no such bin in this organization' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  if v_lot is not null and not exists (select 1 from "better_supabase"."stock_lots" x where x."id" = v_lot and x."tenant_id" = v_line."tenant_id") then
    raise exception 'no such lot in this organization' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  update "better_supabase"."pick_lines" x set
    "picked" = x."picked" + v_quantity,
    "bin_id" = coalesce(v_bin, x."bin_id"),
    "lot_id" = coalesce(v_lot, x."lot_id"),
    "serials" = coalesce(v_serials, x."serials"),
    "status" = case when x."picked" + v_quantity >= x."quantity" then 'picked' else 'open' end,
    "picked_at" = now(),
    "picked_by" = auth.uid()
  where x."id" = v_line."id";
  return "better_supabase"."pick_list_json"(v_list."id");
end;
$$;
revoke execute on function "better_supabase"."record_pick"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."record_pick"(uuid, jsonb) to authenticated, service_role;

-- Finishes a pick list: a line with less picked than asked for becomes short.
-- When it was the last open list of its wave, the wave completes. Needs the
-- same permission as record_pick.
create or replace function "better_supabase"."complete_pick_list"(pick_list_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_list "better_supabase"."pick_lists";
  v_wave "better_supabase"."pick_waves";
  v_short integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_list from "better_supabase"."pick_lists" x where x."id" = complete_pick_list.pick_list_id for update;
  if not found then
    raise exception 'no such pick list' using errcode = 'P0002', hint = 'WAREHOUSE_PICK_LIST_NOT_FOUND';
  end if;
  if not coalesce(((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_list."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_list."tenant_id", 'warehouse.manage'), false))) or ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_list."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_list."tenant_id", 'warehouse.pick'), false))) and coalesce(v_list."assignee_id" is null or v_list."assignee_id" = auth.uid(), false))), false) then
    raise exception 'not allowed to pick from this list' using errcode = '42501', hint = 'WAREHOUSE_FORBIDDEN';
  end if;
  if v_list."status" <> 'open' then
    raise exception 'only an open pick list is completed' using errcode = '55000', hint = 'WAREHOUSE_STATE';
  end if;
  if v_list."wave_id" is not null and (select x."status" from "better_supabase"."pick_waves" x where x."id" = v_list."wave_id") <> 'released' then
    raise exception 'the wave isn''t released yet' using errcode = '55000', hint = 'WAREHOUSE_STATE';
  end if;
  update "better_supabase"."pick_lines" y set "status" = case when y."picked" >= y."quantity" then 'picked' else 'short' end
  where y."pick_list_id" = v_list."id" and y."status" = 'open';
  select count(*) into v_short from "better_supabase"."pick_lines" y where y."pick_list_id" = v_list."id" and y."status" = 'short';
  update "better_supabase"."pick_lists" x set "status" = 'picked', "picked_at" = now()
  where x."id" = v_list."id"
  returning * into v_list;
  null;
  if v_list."wave_id" is not null and not exists (select 1 from "better_supabase"."pick_lists" x where x."wave_id" = v_list."wave_id" and x."status" = 'open') then
    update "better_supabase"."pick_waves" x set "status" = 'completed', "completed_at" = now()
    where x."id" = v_list."wave_id" and x."status" = 'released'
    returning * into v_wave;
    if v_wave."id" is not null then
      null;
    end if;
  end if;
  return "better_supabase"."pick_list_json"(v_list."id");
end;
$$;
revoke execute on function "better_supabase"."complete_pick_list"(uuid) from public, anon;
grant execute on function "better_supabase"."complete_pick_list"(uuid) to authenticated, service_role;

-- A pick list with its lines. Readers see every list; a picker sees the lists
-- assigned to them.
create or replace function "better_supabase"."get_pick_list"(pick_list_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."pick_lists";
begin
  select * into v_row from "better_supabase"."pick_lists" x where x."id" = get_pick_list.pick_list_id;
  if not found or not coalesce((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'warehouse.read'), false))) or v_row."assignee_id" = auth.uid(), false) then
    raise exception 'no such pick list' using errcode = 'P0002', hint = 'WAREHOUSE_PICK_LIST_NOT_FOUND';
  end if;
  return "better_supabase"."pick_list_json"(v_row."id");
end;
$$;
revoke execute on function "better_supabase"."get_pick_list"(uuid) from public, anon;
grant execute on function "better_supabase"."get_pick_list"(uuid) to authenticated, service_role;

-- Pick lists of an organization, newest first. filters is { waveId, status,
-- documentType, documentId, mine: true, limit, offset }. Readers see all of
-- them; everyone else sees the lists assigned to them.
create or replace function "better_supabase"."list_pick_lists"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_pick_lists.filters, '{}'::jsonb);
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_all boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_pick_lists.tenant is not null and coalesce(better_supabase.can('tenant', list_pick_lists.tenant, 'warehouse.read'), false)));
begin
  return coalesce((
    select jsonb_agg("better_supabase"."pick_list_json"(y.id) order by y.created_at desc, y.id)
    from (
      select x."id" as id, x."created_at" as created_at
      from "better_supabase"."pick_lists" x
      where x."tenant_id" = list_pick_lists.tenant
        and (not v_filters ? 'waveId' or x."wave_id" = (v_filters ->> 'waveId')::uuid)
        and (not v_filters ? 'status' or x."status" = v_filters ->> 'status')
        and (not v_filters ? 'documentType' or x."document_type" = v_filters ->> 'documentType')
        and (not v_filters ? 'documentId' or x."document_id" = v_filters ->> 'documentId')
        and ((v_all and (v_filters ->> 'mine') is distinct from 'true') or coalesce(x."assignee_id" = auth.uid(), false))
      order by x."created_at" desc, x."id"
      limit v_limit offset coalesce((v_filters ->> 'offset')::integer, 0)
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_pick_lists"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_pick_lists"(uuid, jsonb) to authenticated, service_role;

-- The pick waves of an organization, newest first, with how many lists each
-- has and how many are still open. Needs warehouse.read.
create or replace function "better_supabase"."list_pick_waves"(tenant uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_pick_waves.tenant is not null and coalesce(better_supabase.can('tenant', list_pick_waves.tenant, 'warehouse.read'), false))) then
    raise exception 'not allowed to read pick waves' using errcode = '42501', hint = 'WAREHOUSE_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'locationId', x."location_id", 'status', x."status", 'releasedAt', x."released_at", 'completedAt', x."completed_at", 'createdAt', x."created_at")
      || jsonb_build_object(
        'lists', (select count(*) from "better_supabase"."pick_lists" z where z."wave_id" = x."id" and z."status" <> 'cancelled'),
        'openLists', (select count(*) from "better_supabase"."pick_lists" z where z."wave_id" = x."id" and z."status" = 'open'))
      order by x."created_at" desc, x."id")
    from "better_supabase"."pick_waves" x where x."tenant_id" = list_pick_waves.tenant
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_pick_waves"(uuid) from public, anon;
grant execute on function "better_supabase"."list_pick_waves"(uuid) to authenticated, service_role;


-- Creates a cycle count plan. input is { name, locationId, everyDays,
-- variantIds, varianceLimitPct, startsOn }. variantIds limits the count to
-- those variants; without it the whole location is counted. Needs
-- warehouse.manage.
create or replace function "better_supabase"."create_count_plan"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."count_plans";
  v_name text;
  v_location uuid;
  v_every integer;
  v_variants uuid[];
  v_limit numeric := 5;
  v_starts date;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_count_plan.tenant is not null and coalesce(better_supabase.can('tenant', create_count_plan.tenant, 'warehouse.manage'), false))) then
    raise exception 'not allowed to manage count plans' using errcode = '42501', hint = 'WAREHOUSE_FORBIDDEN';
  end if;
  if jsonb_typeof(create_count_plan.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  begin
    v_name := trim(create_count_plan.input ->> 'name');
    v_location := (create_count_plan.input ->> 'locationId')::uuid;
    v_every := (create_count_plan.input ->> 'everyDays')::integer;
    v_starts := coalesce((create_count_plan.input ->> 'startsOn')::date, current_date);
    if create_count_plan.input ? 'varianceLimitPct' then
      v_limit := (create_count_plan.input ->> 'varianceLimitPct')::numeric;
    end if;
    if jsonb_typeof(create_count_plan.input -> 'variantIds') = 'array' then
      v_variants := array(select jsonb_array_elements_text(create_count_plan.input -> 'variantIds'))::uuid[];
    end if;
  exception when invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range then
    raise exception 'locationId and variantIds are uuids, everyDays is a whole number, startsOn is a date and varianceLimitPct is a number' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end;
  if coalesce(length(v_name), 0) not between 1 and 200 then
    raise exception 'a plan needs a name of 1 to 200 characters' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  if v_every is null or v_every not between 1 and 3660 then
    raise exception 'everyDays is between 1 and 3660' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  if v_limit is null or v_limit < 0 or v_limit > 9999 then
    raise exception 'varianceLimitPct is between 0 and 9999' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  if not exists (select 1 from "better_supabase"."inventory_locations" x where x."id" = v_location and x."tenant_id" = create_count_plan.tenant) then
    raise exception 'no such location in this organization' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  insert into "better_supabase"."count_plans" ("tenant_id", "name", "location_id", "every_days", "variant_ids", "variance_limit_pct", "next_run_on")
  values (create_count_plan.tenant, v_name, v_location, v_every, v_variants, v_limit, v_starts)
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'locationId', v_row."location_id", 'everyDays', v_row."every_days", 'variantIds', to_jsonb(coalesce(v_row."variant_ids", '{}'::uuid[])), 'varianceLimitPct', v_row."variance_limit_pct"::text, 'nextRunOn', v_row."next_run_on", 'lastRunAt', v_row."last_run_at", 'lastCountId', v_row."last_count_id", 'active', v_row."active", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."create_count_plan"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."create_count_plan"(uuid, jsonb) to authenticated, service_role;

-- The count plans of an organization by next run. Needs warehouse.read.
create or replace function "better_supabase"."list_count_plans"(tenant uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_count_plans.tenant is not null and coalesce(better_supabase.can('tenant', list_count_plans.tenant, 'warehouse.read'), false))) then
    raise exception 'not allowed to read count plans' using errcode = '42501', hint = 'WAREHOUSE_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'locationId', x."location_id", 'everyDays', x."every_days", 'variantIds', to_jsonb(coalesce(x."variant_ids", '{}'::uuid[])), 'varianceLimitPct', x."variance_limit_pct"::text, 'nextRunOn', x."next_run_on", 'lastRunAt', x."last_run_at", 'lastCountId', x."last_count_id", 'active', x."active", 'createdAt', x."created_at") order by x."next_run_on", x."id")
    from "better_supabase"."count_plans" x where x."tenant_id" = list_count_plans.tenant
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_count_plans"(uuid) from public, anon;
grant execute on function "better_supabase"."list_count_plans"(uuid) to authenticated, service_role;

-- Opens the plan's stock count and moves its next run on. A plan whose last
-- count is still open doesn't open another. Not granted to anyone.
create or replace function "better_supabase"."count_plan_run"(plan_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."count_plans";
  v_count uuid;
begin
  select * into v_row from "better_supabase"."count_plans" x where x."id" = count_plan_run.plan_id for update;
  if not found then
    raise exception 'no such count plan' using errcode = 'P0002', hint = 'WAREHOUSE_COUNT_PLAN_NOT_FOUND';
  end if;
  if not v_row."active" then
    raise exception 'the plan is switched off' using errcode = '55000', hint = 'WAREHOUSE_STATE';
  end if;
  if v_row."last_count_id" is not null and exists (
    select 1 from "better_supabase"."stock_counts" x where x."id" = v_row."last_count_id" and x."status" = 'open'
  ) then
    raise exception 'the last count of this plan is still open' using errcode = '55000', hint = 'WAREHOUSE_STATE';
  end if;
  v_count := ("better_supabase"."open_stock_count"(v_row."tenant_id", v_row."location_id",
    jsonb_strip_nulls(jsonb_build_object('note', 'Cycle count: ' || v_row."name", 'variantIds', to_jsonb(v_row."variant_ids")))
  ) ->> 'id')::uuid;
  update "better_supabase"."count_plans" x set
    "last_run_at" = now(),
    "last_count_id" = v_count,
    "next_run_on" = greatest(x."next_run_on", current_date) + x."every_days"
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'locationId', v_row."location_id", 'everyDays', v_row."every_days", 'variantIds', to_jsonb(coalesce(v_row."variant_ids", '{}'::uuid[])), 'varianceLimitPct', v_row."variance_limit_pct"::text, 'nextRunOn', v_row."next_run_on", 'lastRunAt', v_row."last_run_at", 'lastCountId', v_row."last_count_id", 'active', v_row."active", 'createdAt', v_row."created_at") || jsonb_build_object('countId', v_count);
end;
$$;
revoke execute on function "better_supabase"."count_plan_run"(uuid) from public, anon, authenticated;

-- Opens a plan's count now, ahead of its schedule. Opening the count needs
-- inventory.manage as well as warehouse.manage.
create or replace function "better_supabase"."run_count_plan"(plan_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant uuid;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."count_plans" x where x."id" = run_count_plan.plan_id;
  if not found then
    raise exception 'no such count plan' using errcode = 'P0002', hint = 'WAREHOUSE_COUNT_PLAN_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'warehouse.manage'), false))) then
    raise exception 'not allowed to manage count plans' using errcode = '42501', hint = 'WAREHOUSE_FORBIDDEN';
  end if;
  return "better_supabase"."count_plan_run"(run_count_plan.plan_id);
end;
$$;
revoke execute on function "better_supabase"."run_count_plan"(uuid) from public, anon;
grant execute on function "better_supabase"."run_count_plan"(uuid) to authenticated, service_role;

-- Opens the count of every active plan that is due, for a job that runs daily.
-- A plan whose last count is still open waits. Returns the plans and the counts
-- that were opened. Needs warehouse.manage.
create or replace function "better_supabase"."run_due_count_plans"(tenant uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_plan uuid;
  v_result jsonb;
  v_out jsonb := '[]'::jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (run_due_count_plans.tenant is not null and coalesce(better_supabase.can('tenant', run_due_count_plans.tenant, 'warehouse.manage'), false))) then
    raise exception 'not allowed to manage count plans' using errcode = '42501', hint = 'WAREHOUSE_FORBIDDEN';
  end if;
  for v_plan in
    select x."id" from "better_supabase"."count_plans" x
    where x."tenant_id" = run_due_count_plans.tenant and x."active" and x."next_run_on" <= current_date
      and not exists (select 1 from "better_supabase"."stock_counts" z where z."id" = x."last_count_id" and z."status" = 'open')
    order by x."next_run_on", x."id"
    limit least(greatest(coalesce(null, 50), 1), 50)
  loop
    v_result := "better_supabase"."count_plan_run"(v_plan);
    v_out := v_out || jsonb_build_array(jsonb_build_object('planId', v_plan, 'countId', v_result -> 'countId'));
  end loop;
  return v_out;
end;
$$;
revoke execute on function "better_supabase"."run_due_count_plans"(uuid) from public, anon;
grant execute on function "better_supabase"."run_due_count_plans"(uuid) to authenticated, service_role;

-- The variance of a count as a percent of what the books held, per counted
-- line, against the limit of the plan that opened it (5 percent
-- without one). Needs warehouse.read.
create or replace function "better_supabase"."get_cycle_count_variance"(count_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant uuid;
  v_plan uuid;
  v_limit numeric := 5;
  v_lines jsonb;
  v_max numeric;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."stock_counts" x where x."id" = get_cycle_count_variance.count_id;
  if not found then
    raise exception 'no such stock count' using errcode = 'P0002', hint = 'WAREHOUSE_COUNT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'warehouse.read'), false))) then
    raise exception 'not allowed to read counts' using errcode = '42501', hint = 'WAREHOUSE_FORBIDDEN';
  end if;
  select p."id", p."variance_limit_pct" into v_plan, v_limit
  from "better_supabase"."count_plans" p where p."last_count_id" = get_cycle_count_variance.count_id;
  v_limit := coalesce(v_limit, 5);
  select coalesce(jsonb_agg(jsonb_build_object('lineId', y.id, 'variantId', y.variant, 'expected', y.expected::text, 'counted', y.counted::text,
      'variance', (y.counted - y.expected)::text, 'variancePct', round(y.pct, 2)::text) order by y.pct desc, y.id), '[]'::jsonb),
    max(y.pct)
  into v_lines, v_max
  from (
    select z."id" as id, z."variant_id" as variant, z."expected" as expected, z."counted" as counted,
      abs(z."counted" - z."expected") / greatest(z."expected", 1) * 100 as pct
    from "better_supabase"."stock_count_lines" z
    where z."count_id" = get_cycle_count_variance.count_id and z."counted" is not null
  ) y;
  return jsonb_build_object('countId', get_cycle_count_variance.count_id, 'planId', v_plan, 'limitPct', v_limit::text,
    'maxVariancePct', round(coalesce(v_max, 0), 2)::text, 'overLimit', coalesce(v_max, 0) > v_limit, 'lines', v_lines);
end;
$$;
revoke execute on function "better_supabase"."get_cycle_count_variance"(uuid) from public, anon;
grant execute on function "better_supabase"."get_cycle_count_variance"(uuid) to authenticated, service_role;

-- Posts a stock count through the inventory block. A count with a line over the
-- plan's variance limit posts only when approve is true, so a person has seen
-- the numbers first. Needs warehouse.manage, and inventory.manage to post.
create or replace function "better_supabase"."post_cycle_count"(count_id uuid, approve boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant uuid;
  v_variance jsonb;
  v_over boolean;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."stock_counts" x where x."id" = post_cycle_count.count_id;
  if not found then
    raise exception 'no such stock count' using errcode = 'P0002', hint = 'WAREHOUSE_COUNT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'warehouse.manage'), false))) then
    raise exception 'not allowed to post counts' using errcode = '42501', hint = 'WAREHOUSE_FORBIDDEN';
  end if;
  v_variance := "better_supabase"."get_cycle_count_variance"(post_cycle_count.count_id);
  v_over := (v_variance ->> 'overLimit')::boolean;
  if v_over and not coalesce(post_cycle_count.approve, false) then
    raise exception 'a line is off by more than the plan allows, review the count and post it with approve' using errcode = '55000', hint = 'WAREHOUSE_VARIANCE_OVER_LIMIT';
  end if;
  return "better_supabase"."post_stock_count"(post_cycle_count.count_id) || jsonb_build_object('approved', v_over, 'maxVariancePct', v_variance -> 'maxVariancePct');
end;
$$;
revoke execute on function "better_supabase"."post_cycle_count"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."post_cycle_count"(uuid, boolean) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_workspace_ids(text[])') is null then
    create function better_supabase.member_workspace_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."pick_waves";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."pick_waves";
create policy bsb_tenant_scope_select on "better_supabase"."pick_waves" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('warehouse.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pick_waves";
create policy bsb_tenant_scope_insert on "better_supabase"."pick_waves" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."pick_waves";
create policy bsb_tenant_scope_update on "better_supabase"."pick_waves" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pick_waves";
create policy bsb_tenant_scope_delete on "better_supabase"."pick_waves" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."pick_lists";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."pick_lists";
create policy bsb_tenant_scope_select on "better_supabase"."pick_lists" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('warehouse.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pick_lists";
create policy bsb_tenant_scope_insert on "better_supabase"."pick_lists" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."pick_lists";
create policy bsb_tenant_scope_update on "better_supabase"."pick_lists" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pick_lists";
create policy bsb_tenant_scope_delete on "better_supabase"."pick_lists" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."pick_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."pick_lines";
create policy bsb_tenant_scope_select on "better_supabase"."pick_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('warehouse.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pick_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."pick_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."pick_lines";
create policy bsb_tenant_scope_update on "better_supabase"."pick_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pick_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."pick_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."count_plans";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."count_plans";
create policy bsb_tenant_scope_select on "better_supabase"."count_plans" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('warehouse.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."count_plans";
create policy bsb_tenant_scope_insert on "better_supabase"."count_plans" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."count_plans";
create policy bsb_tenant_scope_update on "better_supabase"."count_plans" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."count_plans";
create policy bsb_tenant_scope_delete on "better_supabase"."count_plans" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== data supabase/better-supabase-data/900_better_supabase_166_warehouse.sql
-- better-supabase module: warehouse
-- @bsb-block-data warehouse
-- @bsb-hash sha256:de99a8b453ef3a1d4c58c453b819cfb6b0f618135357c930067906efa72c5215
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('warehouse', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
