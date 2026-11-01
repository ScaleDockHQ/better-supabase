-- better-supabase module: warehouse
-- @bsb-block warehouse@1 managed
-- @bsb-hash sha256:07e3df2b07dc819758ce74f5c869258d0cb620d3f19b2cebd1b32cb1368e97e5
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
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."putaway_rules";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."putaway_rules";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."putaway_rules";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."putaway_rules";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."putaway_rules";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."bin_slots";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."bin_slots";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."bin_slots";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."bin_slots";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."bin_slots";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."variant_sizes";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."variant_sizes";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."variant_sizes";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."variant_sizes";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."variant_sizes";
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
  "route_position" integer check ("route_position" > 0),
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

-- Where a receipt's stock goes: the bin to suggest for a variant (or for any
-- variant), first by priority, up to max_quantity of that variant in the bin.
create table if not exists "better_supabase"."putaway_rules" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "location_id" uuid not null references "better_supabase"."inventory_locations" ("id") on delete cascade,
  "bin_id" uuid not null references "better_supabase"."stock_bins" ("id") on delete cascade,
  "variant_id" uuid references "better_supabase"."product_variants" ("id") on delete cascade,
  "priority" integer not null default 100 check ("priority" between 0 and 10000),
  "max_quantity" numeric(20, 6) check ("max_quantity" > 0),
  "active" boolean not null default true,
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "id")
);
create index if not exists "putaway_rules_lookup_idx" on "better_supabase"."putaway_rules" ("tenant_id", "location_id", "variant_id", "priority") where "active";
create index if not exists "putaway_rules_bin_idx" on "better_supabase"."putaway_rules" ("bin_id");
create index if not exists "putaway_rules_location_idx" on "better_supabase"."putaway_rules" ("location_id");
create index if not exists "putaway_rules_variant_idx" on "better_supabase"."putaway_rules" ("variant_id");
alter table "better_supabase"."putaway_rules" enable row level security;
revoke all on "better_supabase"."putaway_rules" from public, anon, authenticated;
grant select on "better_supabase"."putaway_rules" to authenticated;
grant all on "better_supabase"."putaway_rules" to service_role;
drop policy if exists putaway_rules_read on "better_supabase"."putaway_rules";
create policy putaway_rules_read on "better_supabase"."putaway_rules"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('warehouse.read')));

-- How far a bin is from the dispatch area (walk_rank, lowest is closest) and
-- how much it holds, in the same unit as variant_sizes.size.
create table if not exists "better_supabase"."bin_slots" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "bin_id" uuid not null unique references "better_supabase"."stock_bins" ("id") on delete cascade,
  "walk_rank" integer not null default 0 check ("walk_rank" between 0 and 100000),
  "capacity" numeric(20, 6) check ("capacity" > 0),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "id")
);
alter table "better_supabase"."bin_slots" enable row level security;
revoke all on "better_supabase"."bin_slots" from public, anon, authenticated;
grant select on "better_supabase"."bin_slots" to authenticated;
grant all on "better_supabase"."bin_slots" to service_role;
drop policy if exists bin_slots_read on "better_supabase"."bin_slots";
create policy bin_slots_read on "better_supabase"."bin_slots"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('warehouse.read')));

-- The space one unit of a variant takes in a bin; a variant without a row
-- takes 1.
create table if not exists "better_supabase"."variant_sizes" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "variant_id" uuid not null unique references "better_supabase"."product_variants" ("id") on delete cascade,
  "size" numeric(20, 6) not null check ("size" > 0),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "id")
);
alter table "better_supabase"."variant_sizes" enable row level security;
revoke all on "better_supabase"."variant_sizes" from public, anon, authenticated;
grant select on "better_supabase"."variant_sizes" to authenticated;
grant all on "better_supabase"."variant_sizes" to service_role;
drop policy if exists variant_sizes_read on "better_supabase"."variant_sizes";
create policy variant_sizes_read on "better_supabase"."variant_sizes"
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
        'binId', y."bin_id", 'routePosition', y."route_position", 'lotId', y."lot_id", 'serials', to_jsonb(y."serials"),
        'quantity', y."quantity"::text, 'picked', y."picked"::text, 'status', y."status",
        'pickedAt', y."picked_at", 'pickedBy', y."picked_by")
        order by y."route_position" nulls last, y."variant_id", y."id")
      from "better_supabase"."pick_lines" y where y."pick_list_id" = x."id"
    ), '[]'::jsonb))
  from "better_supabase"."pick_lists" x where x."id" = pick_list_json.pick_list_id
$$;
revoke execute on function "better_supabase"."pick_list_json"(uuid) from public, anon, authenticated;

-- Makes the picker's work item for a pick list that has none. Creating it
-- needs the tasks permission of the caller. Not granted to anyone.
create or replace function "better_supabase"."pick_list_task"(pick_list_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."pick_lists";
  v_task uuid;
begin
  select * into v_row from "better_supabase"."pick_lists" x where x."id" = pick_list_task.pick_list_id and x."task_id" is null for update;
  if not found then
    return;
  end if;
  v_task := ("better_supabase"."create_work_item"(v_row."tenant_id",
    jsonb_build_object('title', 'Pick ' || replace(v_row."document_type", '_', ' ') || ' ' || v_row."document_id"),
    case when v_row."assignee_id" is null then '{}'::uuid[] else array[v_row."assignee_id"] end
  ) ->> 'id')::uuid;
  update "better_supabase"."pick_lists" x set "task_id" = v_task where x."id" = v_row."id";
  insert into "better_supabase"."relations" ("tenant_id", "kind", "source_type", "source_id", "target_type", "target_id", "created_by")
    select v_row."tenant_id", 'created_from', 'work_item', v_task::text, 'pick_list', v_row."id"::text, auth.uid()
    where not exists (
      select 1 from "better_supabase"."relations" x
      where x."kind" = 'created_from' and x."source_type" = 'work_item' and x."source_id" = v_task::text
    );
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
  perform "better_supabase".emit_event('pick_wave.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'name', v_row."name", 'locationId', v_row."location_id", 'status', v_row."status"), 'pick-waves/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/warehouse');
  perform better_supabase.audit_event(
    event_type => 'pick_wave.created',
    category => 'data',
    target_type => 'pick_wave',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'pick wave created',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'name', v_row."name", 'locationId', v_row."location_id", 'status', v_row."status")
  );
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
  perform "better_supabase".emit_event('pick_list.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'waveId', v_row."wave_id", 'locationId', v_row."location_id", 'documentType', v_row."document_type", 'documentId', v_row."document_id", 'status', v_row."status", 'lines', v_lines), 'pick-lists/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/warehouse');
  perform better_supabase.audit_event(
    event_type => 'pick_list.created',
    category => 'data',
    target_type => 'pick_list',
    record_id => v_row."id"::text,
    summary => 'pick list created',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'waveId', v_row."wave_id", 'locationId', v_row."location_id", 'documentType', v_row."document_type", 'documentId', v_row."document_id", 'status', v_row."status", 'lines', v_lines)
  );
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
  perform "better_supabase".emit_event('pick_wave.released', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'name', v_row."name", 'locationId', v_row."location_id", 'status', v_row."status"), 'pick-waves/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/warehouse');
  perform better_supabase.audit_event(
    event_type => 'pick_wave.released',
    category => 'data',
    target_type => 'pick_wave',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'pick wave released',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'name', v_row."name", 'locationId', v_row."location_id", 'status', v_row."status")
  );
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
  if v_list."task_id" is not null then
    update "better_supabase"."work_items" i set "state" = 'completed'
    where i."id" = v_list."task_id"
      and i."state" not in ('completed', 'canceled');
  end if;
  perform "better_supabase".emit_event('pick_list.picked', jsonb_build_object('organizationId', v_list."tenant_id", 'id', v_list."id", 'waveId', v_list."wave_id", 'locationId', v_list."location_id", 'documentType', v_list."document_type", 'documentId', v_list."document_id", 'status', v_list."status", 'short', v_short), 'pick-lists/' || v_list."id"::text, (v_list."tenant_id")::text, null, 'better-supabase/warehouse');
  perform better_supabase.audit_event(
    event_type => 'pick_list.picked',
    category => 'data',
    target_type => 'pick_list',
    record_id => v_list."id"::text,
    summary => 'pick list completed',
    tenant => (v_list."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_list."tenant_id", 'id', v_list."id", 'waveId', v_list."wave_id", 'locationId', v_list."location_id", 'documentType', v_list."document_type", 'documentId', v_list."document_id", 'status', v_list."status", 'short', v_short)
  );
  if v_list."wave_id" is not null and not exists (select 1 from "better_supabase"."pick_lists" x where x."wave_id" = v_list."wave_id" and x."status" = 'open') then
    update "better_supabase"."pick_waves" x set "status" = 'completed', "completed_at" = now()
    where x."id" = v_list."wave_id" and x."status" = 'released'
    returning * into v_wave;
    if v_wave."id" is not null then
      perform "better_supabase".emit_event('pick_wave.completed', jsonb_build_object('organizationId', v_wave."tenant_id", 'id', v_wave."id", 'name', v_wave."name", 'locationId', v_wave."location_id", 'status', v_wave."status"), 'pick-waves/' || v_wave."id"::text, (v_wave."tenant_id")::text, null, 'better-supabase/warehouse');
  perform better_supabase.audit_event(
    event_type => 'pick_wave.completed',
    category => 'data',
    target_type => 'pick_wave',
    record_id => v_wave."id"::text,
    target_label => v_wave."name",
    summary => 'pick wave completed',
    tenant => (v_wave."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_wave."tenant_id", 'id', v_wave."id", 'name', v_wave."name", 'locationId', v_wave."location_id", 'status', v_wave."status")
  );
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
  perform "better_supabase".emit_event('count_plan.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'name', v_row."name", 'locationId', v_row."location_id"), 'count-plans/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/warehouse');
  perform better_supabase.audit_event(
    event_type => 'count_plan.created',
    category => 'data',
    target_type => 'count_plan',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'count plan created',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'name', v_row."name", 'locationId', v_row."location_id")
  );
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
  perform "better_supabase".emit_event('count_plan.executed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'name', v_row."name", 'locationId', v_row."location_id", 'countId', v_count), 'count-plans/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/warehouse');
  perform better_supabase.audit_event(
    event_type => 'count_plan.executed',
    category => 'data',
    target_type => 'count_plan',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'count plan executed',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'name', v_row."name", 'locationId', v_row."location_id", 'countId', v_count)
  );
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


-- One rule as json.
create or replace function "better_supabase"."putaway_rule_json"(rule_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'locationId', x."location_id",
    'binId', x."bin_id", 'variantId', x."variant_id", 'priority', x."priority",
    'maxQuantity', x."max_quantity"::text, 'active', x."active", 'createdAt', x."created_at")
  from "better_supabase"."putaway_rules" x where x."id" = putaway_rule_json.rule_id
$$;
revoke execute on function "better_supabase"."putaway_rule_json"(uuid) from public, anon, authenticated;

-- Creates a putaway rule, or changes the one named by input.id. input is
-- { id, locationId, binId, variantId, priority, maxQuantity, active }: stock of
-- variantId (any variant when absent) goes to binId, lowest priority first,
-- until the bin holds maxQuantity of it. Needs warehouse.manage.
create or replace function "better_supabase"."save_putaway_rule"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."putaway_rules";
  v_id uuid;
  v_location uuid;
  v_bin uuid;
  v_variant uuid;
  v_priority integer;
  v_max numeric;
  v_active boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_putaway_rule.tenant is not null and coalesce(better_supabase.can('tenant', save_putaway_rule.tenant, 'warehouse.manage'), false))) then
    raise exception 'not allowed to manage putaway rules' using errcode = '42501', hint = 'WAREHOUSE_FORBIDDEN';
  end if;
  if jsonb_typeof(save_putaway_rule.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  begin
    v_id := nullif(save_putaway_rule.input ->> 'id', '')::uuid;
    v_location := nullif(save_putaway_rule.input ->> 'locationId', '')::uuid;
    v_bin := nullif(save_putaway_rule.input ->> 'binId', '')::uuid;
    v_variant := nullif(save_putaway_rule.input ->> 'variantId', '')::uuid;
    v_priority := (save_putaway_rule.input ->> 'priority')::integer;
    v_max := (save_putaway_rule.input ->> 'maxQuantity')::numeric;
    v_active := (save_putaway_rule.input ->> 'active')::boolean;
  exception when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'ids are uuids, priority is an integer, maxQuantity a number and active a boolean' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end;
  if v_id is not null then
    select * into v_row from "better_supabase"."putaway_rules" x
    where x."id" = v_id and x."tenant_id" = save_putaway_rule.tenant for update;
    if not found then
      raise exception 'no such putaway rule' using errcode = 'P0002', hint = 'WAREHOUSE_RULE_NOT_FOUND';
    end if;
    v_location := coalesce(v_location, v_row."location_id");
    v_bin := coalesce(v_bin, v_row."bin_id");
    if not (save_putaway_rule.input ? 'variantId') then
      v_variant := v_row."variant_id";
    end if;
    if not (save_putaway_rule.input ? 'maxQuantity') then
      v_max := v_row."max_quantity";
    end if;
    v_priority := coalesce(v_priority, v_row."priority");
    v_active := coalesce(v_active, v_row."active");
  end if;
  if v_location is null or v_bin is null then
    raise exception 'a rule needs a locationId and a binId' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  if not exists (
    select 1 from "better_supabase"."stock_bins" x
    where x."id" = v_bin and x."tenant_id" = save_putaway_rule.tenant and x."location_id" = v_location
  ) then
    raise exception 'the bin has to be in the rule''s location in this organization' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  if v_variant is not null and not exists (
    select 1 from "better_supabase"."product_variants" x where x."id" = v_variant and x."tenant_id" = save_putaway_rule.tenant
  ) then
    raise exception 'no such variant in this organization' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  if coalesce(v_priority, 100) not between 0 and 10000 or coalesce(v_max, 1) <= 0 then
    raise exception 'priority is between 0 and 10000 and maxQuantity is more than 0' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  if v_id is null then
    insert into "better_supabase"."putaway_rules" ("tenant_id", "location_id", "bin_id", "variant_id", "priority", "max_quantity", "active")
    values (save_putaway_rule.tenant, v_location, v_bin, v_variant, coalesce(v_priority, 100), v_max, coalesce(v_active, true))
    returning * into v_row;
  else
    update "better_supabase"."putaway_rules" x set "location_id" = v_location, "bin_id" = v_bin, "variant_id" = v_variant,
      "priority" = v_priority, "max_quantity" = v_max, "active" = v_active
    where x."id" = v_row."id"
    returning * into v_row;
  end if;
  return "better_supabase"."putaway_rule_json"(v_row."id");
end;
$$;
revoke execute on function "better_supabase"."save_putaway_rule"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_putaway_rule"(uuid, jsonb) to authenticated, service_role;

-- Deletes a putaway rule. Returns false when it was already gone. Needs
-- warehouse.manage.
create or replace function "better_supabase"."delete_putaway_rule"(rule_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."putaway_rules";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."putaway_rules" x where x."id" = delete_putaway_rule.rule_id for update;
  if not found then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'warehouse.manage'), false))) then
    raise exception 'not allowed to manage putaway rules' using errcode = '42501', hint = 'WAREHOUSE_FORBIDDEN';
  end if;
  delete from "better_supabase"."putaway_rules" x where x."id" = v_row."id";
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_putaway_rule"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_putaway_rule"(uuid) to authenticated, service_role;

-- The putaway rules of a location, lowest priority first. filters is
-- { locationId, variantId }, both optional. Needs warehouse.read.
create or replace function "better_supabase"."list_putaway_rules"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_location uuid;
  v_variant uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_putaway_rules.tenant is not null and coalesce(better_supabase.can('tenant', list_putaway_rules.tenant, 'warehouse.read'), false))) then
    raise exception 'not allowed to read putaway rules' using errcode = '42501', hint = 'WAREHOUSE_FORBIDDEN';
  end if;
  begin
    v_location := nullif(list_putaway_rules.filters ->> 'locationId', '')::uuid;
    v_variant := nullif(list_putaway_rules.filters ->> 'variantId', '')::uuid;
  exception when invalid_text_representation then
    raise exception 'locationId and variantId are uuids' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end;
  return coalesce((
    select jsonb_agg("better_supabase"."putaway_rule_json"(y.id) order by y.priority, y.id)
    from (
      select x."id" as id, x."priority" as priority from "better_supabase"."putaway_rules" x
      where x."tenant_id" = list_putaway_rules.tenant
        and (v_location is null or x."location_id" = v_location)
        and (v_variant is null or x."variant_id" = v_variant)
      order by x."priority", x."id"
      limit 1000
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_putaway_rules"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_putaway_rules"(uuid, jsonb) to authenticated, service_role;

-- Sets how far a bin is from the dispatch area and how much it holds. input is
-- { binId, walkRank, capacity }: the lowest walkRank is the closest, and
-- capacity is in the unit of variant sizes (no limit when absent). Needs
-- warehouse.manage.
create or replace function "better_supabase"."save_bin_slot"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_bin uuid;
  v_rank integer;
  v_capacity numeric;
  v_row "better_supabase"."bin_slots";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_bin_slot.tenant is not null and coalesce(better_supabase.can('tenant', save_bin_slot.tenant, 'warehouse.manage'), false))) then
    raise exception 'not allowed to manage bin slots' using errcode = '42501', hint = 'WAREHOUSE_FORBIDDEN';
  end if;
  if jsonb_typeof(save_bin_slot.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  begin
    v_bin := (save_bin_slot.input ->> 'binId')::uuid;
    v_rank := coalesce((save_bin_slot.input ->> 'walkRank')::integer, 0);
    v_capacity := (save_bin_slot.input ->> 'capacity')::numeric;
  exception when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'binId is a uuid, walkRank an integer and capacity a number' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end;
  if v_rank not between 0 and 100000 or coalesce(v_capacity, 1) <= 0 then
    raise exception 'walkRank is between 0 and 100000 and capacity is more than 0' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  if not exists (select 1 from "better_supabase"."stock_bins" x where x."id" = v_bin and x."tenant_id" = save_bin_slot.tenant) then
    raise exception 'no such bin in this organization' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  insert into "better_supabase"."bin_slots" ("tenant_id", "bin_id", "walk_rank", "capacity")
  values (save_bin_slot.tenant, v_bin, v_rank, v_capacity)
  on conflict ("bin_id") do update set "walk_rank" = excluded."walk_rank",
    "capacity" = excluded."capacity", "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('binId', v_row."bin_id", 'walkRank', v_row."walk_rank",
    'capacity', v_row."capacity"::text);
end;
$$;
revoke execute on function "better_supabase"."save_bin_slot"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_bin_slot"(uuid, jsonb) to authenticated, service_role;

-- Sets the space one unit of a variant takes in a bin. input is
-- { variantId, size }. Needs warehouse.manage.
create or replace function "better_supabase"."save_variant_size"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_variant uuid;
  v_size numeric;
  v_row "better_supabase"."variant_sizes";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_variant_size.tenant is not null and coalesce(better_supabase.can('tenant', save_variant_size.tenant, 'warehouse.manage'), false))) then
    raise exception 'not allowed to manage variant sizes' using errcode = '42501', hint = 'WAREHOUSE_FORBIDDEN';
  end if;
  if jsonb_typeof(save_variant_size.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  begin
    v_variant := (save_variant_size.input ->> 'variantId')::uuid;
    v_size := (save_variant_size.input ->> 'size')::numeric;
  exception when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'variantId is a uuid and size a number' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end;
  if v_size is null or v_size <= 0 then
    raise exception 'size is more than 0' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  if not exists (select 1 from "better_supabase"."product_variants" x where x."id" = v_variant and x."tenant_id" = save_variant_size.tenant) then
    raise exception 'no such variant in this organization' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  insert into "better_supabase"."variant_sizes" ("tenant_id", "variant_id", "size")
  values (save_variant_size.tenant, v_variant, v_size)
  on conflict ("variant_id") do update set "size" = excluded."size", "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('variantId', v_row."variant_id", 'size', v_row."size"::text);
end;
$$;
revoke execute on function "better_supabase"."save_variant_size"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_variant_size"(uuid, jsonb) to authenticated, service_role;

-- The bins of a location with their slot and how full they are. filters is
-- { locationId }. used is the stock in the bin times the variant sizes.
-- Needs warehouse.read.
create or replace function "better_supabase"."list_bin_slots"(tenant uuid, filters jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_location uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_bin_slots.tenant is not null and coalesce(better_supabase.can('tenant', list_bin_slots.tenant, 'warehouse.read'), false))) then
    raise exception 'not allowed to read bin slots' using errcode = '42501', hint = 'WAREHOUSE_FORBIDDEN';
  end if;
  begin
    v_location := (list_bin_slots.filters ->> 'locationId')::uuid;
  exception when invalid_text_representation then
    raise exception 'locationId is a uuid' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end;
  if v_location is null then
    raise exception 'filters needs a locationId' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('binId', y.bin, 'code', y.code, 'locationId', v_location, 'hold', y.hold,
      'active', y.active, 'walkRank', y.walk_rank, 'capacity', y.capacity::text, 'used', y.used::text)
      order by y.walk_rank nulls last, y.code)
    from (
      select x."id" as bin, x."code" as code, x."hold" as hold, x."active" as active,
        sl."walk_rank" as walk_rank, sl."capacity" as capacity,
        coalesce((
          select sum(c."on_hand" * coalesce(sz."size", 1))
          from "better_supabase"."stock_buckets" c left join "better_supabase"."variant_sizes" sz on sz."variant_id" = c."variant_id"
          where c."bin_id" = x."id"
        ), 0) as used
      from "better_supabase"."stock_bins" x left join "better_supabase"."bin_slots" sl on sl."bin_id" = x."id"
      where x."tenant_id" = list_bin_slots.tenant and x."location_id" = v_location
      order by sl."walk_rank" nulls last, x."code"
      limit 1000
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_bin_slots"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_bin_slots"(uuid, jsonb) to authenticated, service_role;

-- Where stock of a variant goes in a location. Rule bins come first (a rule for
-- the variant before one for any variant, then by priority), then bins that
-- already hold it, then the other active bins by walk rank and how empty they
-- are. Bins on hold or inactive are skipped; a bin takes no more than its
-- rule's maxQuantity of the variant or its slot capacity. Not granted to
-- anyone.
create or replace function "better_supabase"."putaway_plan"(plan_tenant uuid, plan_location uuid, plan_variant uuid, plan_quantity numeric)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_left numeric := plan_quantity;
  v_size numeric;
  v_room numeric;
  v_take numeric;
  v_placements jsonb := '[]'::jsonb;
  rec record;
begin
  select coalesce((select x."size" from "better_supabase"."variant_sizes" x where x."variant_id" = plan_variant), 1) into v_size;
  for rec in
    with held as (
      select c."bin_id" as bin,
        coalesce(sum(c."on_hand") filter (where c."variant_id" = plan_variant), 0) as of_variant,
        sum(c."on_hand" * coalesce(sz."size", 1)) as used
      from "better_supabase"."stock_buckets" c left join "better_supabase"."variant_sizes" sz on sz."variant_id" = c."variant_id"
      where c."tenant_id" = plan_tenant and c."location_id" = plan_location and c."bin_id" is not null
      group by c."bin_id"
    ),
    cand as (
      select distinct on (y.bin) y.bin, y.tier, y.rank, y.rule_id, y.max_quantity
      from (
        select x."bin_id" as bin, case when x."variant_id" is null then 1 else 0 end as tier,
          x."priority" as rank, x."id" as rule_id, x."max_quantity" as max_quantity
        from "better_supabase"."putaway_rules" x
        where x."tenant_id" = plan_tenant and x."location_id" = plan_location and x."active"
          and (x."variant_id" is null or x."variant_id" = plan_variant)
        union all
        select h.bin, 2, 0, null::uuid, null::numeric from held h where h.of_variant > 0
        union all
        select x."id", 3, coalesce(sl."walk_rank", 100001), null::uuid, null::numeric
        from "better_supabase"."stock_bins" x left join "better_supabase"."bin_slots" sl on sl."bin_id" = x."id"
        where x."tenant_id" = plan_tenant and x."location_id" = plan_location
      ) y
      order by y.bin, y.tier, y.rank
    )
    select c.bin, bn."code" as code, c.tier, c.rank, c.rule_id, c.max_quantity,
      coalesce(h.of_variant, 0) as of_variant, coalesce(h.used, 0) as used, sl."capacity" as capacity
    from cand c
    join "better_supabase"."stock_bins" bn on bn."id" = c.bin
    left join held h on h.bin = c.bin
    left join "better_supabase"."bin_slots" sl on sl."bin_id" = c.bin
    where bn."active" and not bn."hold" and bn."location_id" = plan_location and bn."tenant_id" = plan_tenant
    order by c.tier, c.rank, case when c.tier = 2 then -coalesce(h.of_variant, 0) else coalesce(h.used, 0) end, bn."code"
  loop
    exit when v_left <= 0;
    v_room := least(
      case when rec.max_quantity is null then 'Infinity'::numeric else rec.max_quantity - rec.of_variant end,
      case when rec.capacity is null then 'Infinity'::numeric else (rec.capacity - rec.used) / v_size end
    );
    continue when v_room <= 0;
    v_take := least(v_left, trunc(v_room, 6));
    continue when v_take <= 0;
    v_placements := v_placements || jsonb_build_object('binId', rec.bin, 'binCode', rec.code,
      'quantity', v_take::text, 'source', case when rec.tier < 2 then 'rule' when rec.tier = 2 then 'stock' else 'free' end,
      'ruleId', rec.rule_id);
    v_left := v_left - v_take;
  end loop;
  return jsonb_build_object('locationId', plan_location, 'variantId', plan_variant, 'quantity', plan_quantity::text,
    'placements', v_placements, 'unassigned', v_left::text);
end;
$$;
revoke execute on function "better_supabase"."putaway_plan"(uuid, uuid, uuid, numeric) from public, anon, authenticated;

-- Suggests bins for stock about to be put away. input is { locationId,
-- variantId, quantity }. Nothing moves: the suggestion lists each bin with the
-- quantity it takes, why (rule, stock or free), and what is left over when no
-- bin has room. Needs warehouse.read or warehouse.pick.
create or replace function "better_supabase"."suggest_putaway"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_location uuid;
  v_variant uuid;
  v_quantity numeric;
begin
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (suggest_putaway.tenant is not null and coalesce(better_supabase.can('tenant', suggest_putaway.tenant, 'warehouse.read'), false))) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (suggest_putaway.tenant is not null and coalesce(better_supabase.can('tenant', suggest_putaway.tenant, 'warehouse.pick'), false)))) then
    raise exception 'not allowed to read putaway suggestions' using errcode = '42501', hint = 'WAREHOUSE_FORBIDDEN';
  end if;
  if jsonb_typeof(suggest_putaway.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  begin
    v_location := (suggest_putaway.input ->> 'locationId')::uuid;
    v_variant := (suggest_putaway.input ->> 'variantId')::uuid;
    v_quantity := (suggest_putaway.input ->> 'quantity')::numeric;
  exception when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'locationId and variantId are uuids and quantity is a number' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end;
  if v_quantity is null or v_quantity <= 0 then
    raise exception 'quantity is more than 0' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  if not exists (select 1 from "better_supabase"."inventory_locations" x where x."id" = v_location and x."tenant_id" = suggest_putaway.tenant) then
    raise exception 'no such location in this organization' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  if not exists (select 1 from "better_supabase"."product_variants" x where x."id" = v_variant and x."tenant_id" = suggest_putaway.tenant) then
    raise exception 'no such variant in this organization' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  return "better_supabase"."putaway_plan"(suggest_putaway.tenant, v_location, v_variant, v_quantity);
end;
$$;
revoke execute on function "better_supabase"."suggest_putaway"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."suggest_putaway"(uuid, jsonb) to authenticated, service_role;

-- Suggests bins for every variant of a goods receipt, at the receipt's
-- location. Lines of one variant are planned together. Variants are planned
-- one by one, so two variants can be suggested the same bin when it has room
-- for each but not both. Needs warehouse.read or warehouse.pick.
create or replace function "better_supabase"."suggest_receipt_putaway"(receipt_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_receipt "better_supabase"."inventory_receipts";
  v_out jsonb := '[]'::jsonb;
  rec record;
begin
  select * into v_receipt from "better_supabase"."inventory_receipts" x where x."id" = suggest_receipt_putaway.receipt_id;
  if not found then
    raise exception 'no such goods receipt' using errcode = 'P0002', hint = 'WAREHOUSE_RECEIPT_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_receipt."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_receipt."tenant_id", 'warehouse.read'), false))) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_receipt."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_receipt."tenant_id", 'warehouse.pick'), false)))) then
    raise exception 'not allowed to read putaway suggestions' using errcode = '42501', hint = 'WAREHOUSE_FORBIDDEN';
  end if;
  if v_receipt."location_id" is null then
    raise exception 'the receipt has no location' using errcode = '55000', hint = 'WAREHOUSE_STATE';
  end if;
  for rec in
    select x."variant_id" as variant, sum(x."quantity") as quantity
    from "better_supabase"."inventory_receipt_lines" x
    where x."receipt_id" = v_receipt."id" and x."quantity" > 0
    group by x."variant_id"
    order by x."variant_id"
  loop
    v_out := v_out || "better_supabase"."putaway_plan"(v_receipt."tenant_id", v_receipt."location_id", rec.variant, rec.quantity);
  end loop;
  return v_out;
end;
$$;
revoke execute on function "better_supabase"."suggest_receipt_putaway"(uuid) from public, anon;
grant execute on function "better_supabase"."suggest_receipt_putaway"(uuid) to authenticated, service_role;

-- Suggests where the fastest movers of a location should live. input is
-- { locationId, days, limit }: the variants most picked in the last days
-- (default 30), at most limit of them (default 50), each get the closest bin
-- with a slot that holds their stock, fastest first. A variant already in a bin
-- as close or closer stays (action keep). Nothing moves. Needs warehouse.read.
create or replace function "better_supabase"."suggest_slotting"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_location uuid;
  v_days integer;
  v_limit integer;
  v_taken uuid[] := '{}';
  v_bin uuid;
  v_rank integer;
  v_current_rank integer;
  v_action text;
  v_suggested uuid;
  v_out jsonb := '[]'::jsonb;
  rec record;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (suggest_slotting.tenant is not null and coalesce(better_supabase.can('tenant', suggest_slotting.tenant, 'warehouse.read'), false))) then
    raise exception 'not allowed to read slotting suggestions' using errcode = '42501', hint = 'WAREHOUSE_FORBIDDEN';
  end if;
  if jsonb_typeof(suggest_slotting.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  begin
    v_location := (suggest_slotting.input ->> 'locationId')::uuid;
    v_days := coalesce((suggest_slotting.input ->> 'days')::integer, 30);
    v_limit := coalesce((suggest_slotting.input ->> 'limit')::integer, 50);
  exception when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'locationId is a uuid, days and limit are integers' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end;
  if v_days not between 1 and 365 or v_limit not between 1 and 500 then
    raise exception 'days is between 1 and 365 and limit between 1 and 500' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  if not exists (select 1 from "better_supabase"."inventory_locations" x where x."id" = v_location and x."tenant_id" = suggest_slotting.tenant) then
    raise exception 'no such location in this organization' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  for rec in
    with moves as (
      select y."variant_id" as variant, sum(y."picked") as velocity, count(*) as picks
      from "better_supabase"."pick_lines" y join "better_supabase"."pick_lists" x on x."id" = y."pick_list_id"
      where x."tenant_id" = suggest_slotting.tenant and x."location_id" = v_location
        and y."picked" > 0 and y."picked_at" >= now() - make_interval(days => v_days)
      group by y."variant_id"
      order by sum(y."picked") desc, y."variant_id"
      limit v_limit
    )
    select m.variant, m.velocity, m.picks,
      coalesce((select sum(c."on_hand") from "better_supabase"."stock_buckets" c
        where c."tenant_id" = suggest_slotting.tenant and c."location_id" = v_location
          and c."variant_id" = m.variant and c."bin_id" is not null), 0) as on_hand,
      (select c."bin_id" from "better_supabase"."stock_buckets" c
        where c."tenant_id" = suggest_slotting.tenant and c."location_id" = v_location
          and c."variant_id" = m.variant and c."bin_id" is not null
        order by c."on_hand" desc, c."bin_id" limit 1) as current_bin,
      coalesce((select sz."size" from "better_supabase"."variant_sizes" sz where sz."variant_id" = m.variant), 1) as size
    from moves m
    order by m.velocity desc, m.variant
  loop
    v_current_rank := (select sl."walk_rank" from "better_supabase"."bin_slots" sl where sl."bin_id" = rec.current_bin);
    v_bin := null;
    v_rank := null;
    select x."id", sl."walk_rank" into v_bin, v_rank
    from "better_supabase"."stock_bins" x join "better_supabase"."bin_slots" sl on sl."bin_id" = x."id"
    where x."tenant_id" = suggest_slotting.tenant and x."location_id" = v_location
      and x."active" and not x."hold" and not (x."id" = any(v_taken))
      and (sl."capacity" is null or sl."capacity" >= rec.on_hand * rec.size)
    order by sl."walk_rank", x."code"
    limit 1;
    if v_bin is null or (v_current_rank is not null and v_current_rank <= v_rank) or v_bin = rec.current_bin then
      v_action := 'keep';
      v_suggested := rec.current_bin;
    else
      v_action := 'move';
      v_suggested := v_bin;
    end if;
    if v_suggested is not null then
      v_taken := v_taken || v_suggested;
    end if;
    v_out := v_out || jsonb_build_object('variantId', rec.variant, 'velocity', rec.velocity::text, 'picks', rec.picks,
      'onHand', rec.on_hand::text, 'currentBinId', rec.current_bin, 'suggestedBinId', v_suggested, 'action', v_action);
  end loop;
  return v_out;
end;
$$;
revoke execute on function "better_supabase"."suggest_slotting"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."suggest_slotting"(uuid, jsonb) to authenticated, service_role;

-- Sets the order a picker walks an open pick list. line_ids lists open lines of
-- the list in walking order; open lines left out follow in variant order.
-- Picked lines keep no position. Needs the same permission as record_pick.
create or replace function "better_supabase"."set_pick_route"(pick_list_id uuid, line_ids uuid[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_list "better_supabase"."pick_lists";
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_list from "better_supabase"."pick_lists" x where x."id" = set_pick_route.pick_list_id for update;
  if not found then
    raise exception 'no such pick list' using errcode = 'P0002', hint = 'WAREHOUSE_PICK_LIST_NOT_FOUND';
  end if;
  if not coalesce(((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_list."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_list."tenant_id", 'warehouse.manage'), false))) or ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_list."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_list."tenant_id", 'warehouse.pick'), false))) and coalesce(v_list."assignee_id" is null or v_list."assignee_id" = auth.uid(), false))), false) then
    raise exception 'not allowed to pick from this list' using errcode = '42501', hint = 'WAREHOUSE_FORBIDDEN';
  end if;
  if v_list."status" <> 'open' then
    raise exception 'only an open pick list has a route' using errcode = '55000', hint = 'WAREHOUSE_STATE';
  end if;
  if (select count(distinct t) from unnest(set_pick_route.line_ids) t) <> coalesce(cardinality(set_pick_route.line_ids), 0) then
    raise exception 'a line is on the route once' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  select count(*) into v_count from "better_supabase"."pick_lines" y
  where y."pick_list_id" = v_list."id" and y."status" = 'open' and y."id" = any(coalesce(set_pick_route.line_ids, '{}'));
  if v_count <> coalesce(cardinality(set_pick_route.line_ids), 0) then
    raise exception 'the route lists open lines of this pick list' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  update "better_supabase"."pick_lines" y set "route_position" = o.position
  from (
    select y2."id" as id, row_number() over (
      order by coalesce(array_position(coalesce(set_pick_route.line_ids, '{}'), y2."id"), 1000000), y2."variant_id", y2."id"
    ) as position
    from "better_supabase"."pick_lines" y2 where y2."pick_list_id" = v_list."id" and y2."status" = 'open'
  ) o
  where y."id" = o.id;
  return "better_supabase"."pick_list_json"(v_list."id");
end;
$$;
revoke execute on function "better_supabase"."set_pick_route"(uuid, uuid[]) from public, anon;
grant execute on function "better_supabase"."set_pick_route"(uuid, uuid[]) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
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
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('warehouse.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pick_waves";
create policy bsb_tenant_scope_insert on "better_supabase"."pick_waves" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."pick_waves";
create policy bsb_tenant_scope_update on "better_supabase"."pick_waves" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pick_waves";
create policy bsb_tenant_scope_delete on "better_supabase"."pick_waves" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."pick_lists";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."pick_lists";
create policy bsb_tenant_scope_select on "better_supabase"."pick_lists" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('warehouse.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pick_lists";
create policy bsb_tenant_scope_insert on "better_supabase"."pick_lists" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."pick_lists";
create policy bsb_tenant_scope_update on "better_supabase"."pick_lists" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pick_lists";
create policy bsb_tenant_scope_delete on "better_supabase"."pick_lists" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."pick_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."pick_lines";
create policy bsb_tenant_scope_select on "better_supabase"."pick_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('warehouse.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pick_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."pick_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."pick_lines";
create policy bsb_tenant_scope_update on "better_supabase"."pick_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pick_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."pick_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."count_plans";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."count_plans";
create policy bsb_tenant_scope_select on "better_supabase"."count_plans" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('warehouse.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."count_plans";
create policy bsb_tenant_scope_insert on "better_supabase"."count_plans" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."count_plans";
create policy bsb_tenant_scope_update on "better_supabase"."count_plans" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."count_plans";
create policy bsb_tenant_scope_delete on "better_supabase"."count_plans" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."putaway_rules";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."putaway_rules";
create policy bsb_tenant_scope_select on "better_supabase"."putaway_rules" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('warehouse.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."putaway_rules";
create policy bsb_tenant_scope_insert on "better_supabase"."putaway_rules" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."putaway_rules";
create policy bsb_tenant_scope_update on "better_supabase"."putaway_rules" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."putaway_rules";
create policy bsb_tenant_scope_delete on "better_supabase"."putaway_rules" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."bin_slots";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."bin_slots";
create policy bsb_tenant_scope_select on "better_supabase"."bin_slots" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('warehouse.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."bin_slots";
create policy bsb_tenant_scope_insert on "better_supabase"."bin_slots" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."bin_slots";
create policy bsb_tenant_scope_update on "better_supabase"."bin_slots" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."bin_slots";
create policy bsb_tenant_scope_delete on "better_supabase"."bin_slots" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."variant_sizes";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."variant_sizes";
create policy bsb_tenant_scope_select on "better_supabase"."variant_sizes" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('warehouse.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."variant_sizes";
create policy bsb_tenant_scope_insert on "better_supabase"."variant_sizes" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."variant_sizes";
create policy bsb_tenant_scope_update on "better_supabase"."variant_sizes" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."variant_sizes";
create policy bsb_tenant_scope_delete on "better_supabase"."variant_sizes" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.warehouse.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."actor_may_write"()
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."actor_may_write"() $$;
revoke execute on function "api"."actor_may_write"() from public;
grant execute on function "api"."actor_may_write"() to anon, authenticated, service_role;

create or replace function "api"."raise_actor_readonly"()
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."raise_actor_readonly"() $$;
revoke execute on function "api"."raise_actor_readonly"() from public;
grant execute on function "api"."raise_actor_readonly"() to anon, authenticated, service_role;

create or replace function "api"."create_pick_wave"(tenant uuid, input jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_pick_wave"($1, $2) $$;
revoke execute on function "api"."create_pick_wave"(uuid, jsonb) from public, anon;
grant execute on function "api"."create_pick_wave"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."create_pick_list"(tenant uuid, input jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_pick_list"($1, $2) $$;
revoke execute on function "api"."create_pick_list"(uuid, jsonb) from public, anon;
grant execute on function "api"."create_pick_list"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."release_pick_wave"(wave_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."release_pick_wave"($1) $$;
revoke execute on function "api"."release_pick_wave"(uuid) from public, anon;
grant execute on function "api"."release_pick_wave"(uuid) to authenticated, service_role;

create or replace function "api"."cancel_pick_wave"(wave_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."cancel_pick_wave"($1) $$;
revoke execute on function "api"."cancel_pick_wave"(uuid) from public, anon;
grant execute on function "api"."cancel_pick_wave"(uuid) to authenticated, service_role;

create or replace function "api"."record_pick"(line_id uuid, attrs jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_pick"($1, $2) $$;
revoke execute on function "api"."record_pick"(uuid, jsonb) from public, anon;
grant execute on function "api"."record_pick"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."complete_pick_list"(pick_list_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."complete_pick_list"($1) $$;
revoke execute on function "api"."complete_pick_list"(uuid) from public, anon;
grant execute on function "api"."complete_pick_list"(uuid) to authenticated, service_role;

create or replace function "api"."get_pick_list"(pick_list_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_pick_list"($1) $$;
revoke execute on function "api"."get_pick_list"(uuid) from public, anon;
grant execute on function "api"."get_pick_list"(uuid) to authenticated, service_role;

create or replace function "api"."list_pick_lists"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_pick_lists"($1, $2) $$;
revoke execute on function "api"."list_pick_lists"(uuid, jsonb) from public, anon;
grant execute on function "api"."list_pick_lists"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."list_pick_waves"(tenant uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_pick_waves"($1) $$;
revoke execute on function "api"."list_pick_waves"(uuid) from public, anon;
grant execute on function "api"."list_pick_waves"(uuid) to authenticated, service_role;

create or replace function "api"."create_count_plan"(tenant uuid, input jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_count_plan"($1, $2) $$;
revoke execute on function "api"."create_count_plan"(uuid, jsonb) from public, anon;
grant execute on function "api"."create_count_plan"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."list_count_plans"(tenant uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_count_plans"($1) $$;
revoke execute on function "api"."list_count_plans"(uuid) from public, anon;
grant execute on function "api"."list_count_plans"(uuid) to authenticated, service_role;

create or replace function "api"."run_count_plan"(plan_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."run_count_plan"($1) $$;
revoke execute on function "api"."run_count_plan"(uuid) from public, anon;
grant execute on function "api"."run_count_plan"(uuid) to authenticated, service_role;

create or replace function "api"."run_due_count_plans"(tenant uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."run_due_count_plans"($1) $$;
revoke execute on function "api"."run_due_count_plans"(uuid) from public, anon;
grant execute on function "api"."run_due_count_plans"(uuid) to authenticated, service_role;

create or replace function "api"."get_cycle_count_variance"(count_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_cycle_count_variance"($1) $$;
revoke execute on function "api"."get_cycle_count_variance"(uuid) from public, anon;
grant execute on function "api"."get_cycle_count_variance"(uuid) to authenticated, service_role;

create or replace function "api"."post_cycle_count"(count_id uuid, approve boolean default false)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."post_cycle_count"($1, $2) $$;
revoke execute on function "api"."post_cycle_count"(uuid, boolean) from public, anon;
grant execute on function "api"."post_cycle_count"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."save_putaway_rule"(tenant uuid, input jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_putaway_rule"($1, $2) $$;
revoke execute on function "api"."save_putaway_rule"(uuid, jsonb) from public, anon;
grant execute on function "api"."save_putaway_rule"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."delete_putaway_rule"(rule_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_putaway_rule"($1) $$;
revoke execute on function "api"."delete_putaway_rule"(uuid) from public, anon;
grant execute on function "api"."delete_putaway_rule"(uuid) to authenticated, service_role;

create or replace function "api"."list_putaway_rules"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_putaway_rules"($1, $2) $$;
revoke execute on function "api"."list_putaway_rules"(uuid, jsonb) from public, anon;
grant execute on function "api"."list_putaway_rules"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."save_bin_slot"(tenant uuid, input jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_bin_slot"($1, $2) $$;
revoke execute on function "api"."save_bin_slot"(uuid, jsonb) from public, anon;
grant execute on function "api"."save_bin_slot"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."save_variant_size"(tenant uuid, input jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_variant_size"($1, $2) $$;
revoke execute on function "api"."save_variant_size"(uuid, jsonb) from public, anon;
grant execute on function "api"."save_variant_size"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."list_bin_slots"(tenant uuid, filters jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_bin_slots"($1, $2) $$;
revoke execute on function "api"."list_bin_slots"(uuid, jsonb) from public, anon;
grant execute on function "api"."list_bin_slots"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."suggest_putaway"(tenant uuid, input jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."suggest_putaway"($1, $2) $$;
revoke execute on function "api"."suggest_putaway"(uuid, jsonb) from public, anon;
grant execute on function "api"."suggest_putaway"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."suggest_receipt_putaway"(receipt_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."suggest_receipt_putaway"($1) $$;
revoke execute on function "api"."suggest_receipt_putaway"(uuid) from public, anon;
grant execute on function "api"."suggest_receipt_putaway"(uuid) to authenticated, service_role;

create or replace function "api"."suggest_slotting"(tenant uuid, input jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."suggest_slotting"($1, $2) $$;
revoke execute on function "api"."suggest_slotting"(uuid, jsonb) from public, anon;
grant execute on function "api"."suggest_slotting"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."set_pick_route"(pick_list_id uuid, line_ids uuid[])
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_pick_route"($1, $2) $$;
revoke execute on function "api"."set_pick_route"(uuid, uuid[]) from public, anon;
grant execute on function "api"."set_pick_route"(uuid, uuid[]) to authenticated, service_role;

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
