-- better-supabase module: option-sets
-- @bsb-block option-sets@1 managed
-- @bsb-hash sha256:56cbf950001f6d8e6fa9033bc80679579dd3d89498b14078de8370aa5d462f13
-- Tenant-editable items for a field such as priority or severity: ordered items with a label, color, icon and a level written to the record's own column, replacement when an item is removed, and starter items per brand.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Option sets (ADR 0243): tenant-editable items for a field such as priority,
-- each with a level that is written to the record's own column, and starter
-- items per brand.

create table "better_supabase"."option_sets" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "field" text not null constraint bsb_option_sets_field_check check ("field" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "scope_id" text,
  "key" text not null constraint bsb_option_sets_key_check check ("key" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "name" text not null constraint bsb_option_sets_name_check check (length("name") >= 1 and length("name") <= 200),
  "is_default" boolean not null default false,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique nulls not distinct ("tenant_id", "subject_type", "field", "scope_id", "key")
);
create unique index option_sets_default_idx on "better_supabase"."option_sets" ("tenant_id", "subject_type", "field", coalesce("scope_id", ''))
  where "is_default" and "archived_at" is null;
alter table "better_supabase"."option_sets" enable row level security;
revoke all on "better_supabase"."option_sets" from public, anon, authenticated;
grant select on "better_supabase"."option_sets" to authenticated;
grant all on "better_supabase"."option_sets" to service_role;
create policy bsb_option_sets_read on "better_supabase"."option_sets"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('option_sets.read')));

create table "better_supabase"."option_set_items" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "option_set_id" uuid not null references "better_supabase"."option_sets" ("id") on delete cascade,
  "key" text not null constraint bsb_option_set_items_key_check check ("key" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "system_key" text,
  "label" text not null constraint bsb_option_set_items_label_check check (length("label") >= 1 and length("label") <= 200),
  "color" text constraint bsb_option_set_items_color_check check ("color" is null or length("color") <= 50),
  "icon" text constraint bsb_option_set_items_icon_check check ("icon" is null or length("icon") <= 100),
  "rank" text collate "C" not null default 'V',
  "level" integer not null,
  "description" text constraint bsb_option_set_items_description_check check ("description" is null or length("description") <= 1000),
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("option_set_id", "key")
);
create unique index option_set_items_system_key_idx on "better_supabase"."option_set_items" ("option_set_id", "system_key") where "system_key" is not null;
create index option_set_items_set_idx on "better_supabase"."option_set_items" ("option_set_id", "rank");
alter table "better_supabase"."option_set_items" enable row level security;
revoke all on "better_supabase"."option_set_items" from public, anon, authenticated;
grant select on "better_supabase"."option_set_items" to authenticated;
grant all on "better_supabase"."option_set_items" to service_role;
create policy bsb_option_set_items_read on "better_supabase"."option_set_items"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('option_sets.read')));

-- The column that holds the chosen item, on each bound table.
alter table "better_supabase"."work_items" add column "priority_option_id" uuid references "better_supabase"."option_set_items" ("id") on delete set null;
create index "bsb_work_item_priority_option_id_idx" on "better_supabase"."work_items" ("priority_option_id");

-- The default option set of a field in a tenant and scope. The first call
-- creates it from the field's item template in on.
create or replace function "better_supabase"."default_option_set"(tenant uuid, subject_type text, field text, scope_id text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_brand text;
begin
  select x."id" into v_id from "better_supabase"."option_sets" x
  where x."tenant_id" = default_option_set.tenant
    and x."subject_type" = default_option_set.subject_type
    and x."field" = default_option_set.field
    and x."scope_id" is not distinct from default_option_set.scope_id
    and x."archived_at" is null
  order by x."is_default" desc, x."created_at", x."id"
  limit 1;
  if v_id is not null then
    return v_id;
  end if;
      if default_option_set.subject_type = 'work_item' and default_option_set.field = 'priority' then
      insert into "better_supabase"."option_sets" ("tenant_id", "subject_type", "field", "scope_id", "key", "name", "is_default")
      values (default_option_set.tenant, default_option_set.subject_type, default_option_set.field, default_option_set.scope_id, 'default', 'Default', true)
      on conflict do nothing
      returning "id" into v_id;
      if v_id is null then
        select x."id" into v_id from "better_supabase"."option_sets" x
        where x."tenant_id" = default_option_set.tenant
          and x."subject_type" = default_option_set.subject_type
          and x."field" = default_option_set.field
          and x."scope_id" is not distinct from default_option_set.scope_id
          and x."archived_at" is null
        order by x."is_default" desc, x."created_at", x."id"
        limit 1;
        if v_id is null then
          raise exception 'the default option set of this field is archived' using errcode = '55000', hint = 'OPTION_SET_UNAVAILABLE';
        end if;
        return v_id;
      end if;
      insert into "better_supabase"."option_set_items" ("tenant_id", "option_set_id", "key", "system_key", "label", "color", "icon", "rank", "level")
      select default_option_set.tenant, v_id, x.key, x.key, x.label, x.color, x.icon, x.rank, x.level
      from (values
          ('none', 'None', 0, null::text, null::text, 'A'),
          ('low', 'Low', 1, null::text, null::text, 'K'),
          ('medium', 'Medium', 2, null::text, null::text, 'U'),
          ('high', 'High', 3, null::text, null::text, 'e'),
          ('urgent', 'Urgent', 4, null::text, null::text, 'o')
      ) x(key, label, level, color, icon, rank);
    else
      raise exception 'this field has no option set binding' using errcode = '22023', hint = 'OPTION_SET_FIELD_UNKNOWN';
    end if;
  return v_id;
end;
$$;
revoke execute on function "better_supabase"."default_option_set"(uuid, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."default_option_set"(uuid, text, text, text) to service_role;

create or replace function better_supabase.bsb_option_work_item_priority()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_level integer;
begin
  if tg_op = 'UPDATE' and new."priority_option_id" is not distinct from old."priority_option_id" and new."priority" is not distinct from old."priority" then
    return new;
  end if;
  if new."priority_option_id" is not null and (tg_op = 'INSERT' or new."priority_option_id" is distinct from old."priority_option_id") then
    select x."level" into v_level
    from "better_supabase"."option_set_items" x
    join "better_supabase"."option_sets" y on y."id" = x."option_set_id"
    where x."id" = new."priority_option_id"
      and x."archived_at" is null
      and y."archived_at" is null
      and y."tenant_id"::text = new."tenant_id"::text
      and y."subject_type" = 'work_item'
      and y."field" = 'priority'
      and y."scope_id" is not distinct from null;
    if not found then
      raise exception 'the item is not an active item of this record''s option set' using errcode = '22023', hint = 'OPTION_SET_ITEM_INVALID';
    end if;
    new."priority" := v_level;
  end if;
  return new;
end;
$$;
create trigger bsb_option_work_item_priority before insert or update of "priority", "priority_option_id" on "better_supabase"."work_items"
for each row execute function better_supabase.bsb_option_work_item_priority();

-- The option sets of a tenant with their active items, ordered by rank.
-- filters is { subjectType, field, scopeId, includeArchived }.
create or replace function "better_supabase"."list_option_sets"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_filters jsonb := coalesce(list_option_sets.filters, '{}'::jsonb);
  v_archived boolean := coalesce((v_filters ->> 'includeArchived')::boolean, false);
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_option_sets.tenant, 'option_sets.read'), false)) then
    raise exception 'not allowed to read option sets' using errcode = '42501', hint = 'OPTION_SET_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(to_jsonb(y) || jsonb_build_object('items', coalesce((
      select jsonb_agg(to_jsonb(z) order by z."rank" collate "C", z."id")
      from "better_supabase"."option_set_items" z
      where z."option_set_id" = y."id" and (v_archived or z."archived_at" is null)
    ), '[]'::jsonb)) order by y."is_default" desc, y."created_at", y."id")
    from "better_supabase"."option_sets" y
    where y."tenant_id" = list_option_sets.tenant
      and (v_archived or y."archived_at" is null)
      and (not v_filters ? 'subjectType' or y."subject_type" = v_filters ->> 'subjectType')
      and (not v_filters ? 'field' or y."field" = v_filters ->> 'field')
      and (not v_filters ? 'scopeId' or y."scope_id" is not distinct from (v_filters ->> 'scopeId'))
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_option_sets"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_option_sets"(uuid, jsonb) to authenticated, service_role;

-- The default option set of a field, created from its template on first use.
-- Returns it with its items.
create or replace function "better_supabase"."ensure_option_set"(tenant uuid, subject_type text, field text, scope_id text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_set uuid;
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', ensure_option_set.tenant, 'option_sets.read'), false)) then
    raise exception 'not allowed to read option sets' using errcode = '42501', hint = 'OPTION_SET_FORBIDDEN';
  end if;
  v_set := "better_supabase"."default_option_set"(ensure_option_set.tenant, ensure_option_set.subject_type, ensure_option_set.field, ensure_option_set.scope_id);
  return (select to_jsonb(y) || jsonb_build_object('items', coalesce((
      select jsonb_agg(to_jsonb(z) order by z."rank" collate "C", z."id")
      from "better_supabase"."option_set_items" z
      where z."option_set_id" = y."id" and (false or z."archived_at" is null)
    ), '[]'::jsonb)) from "better_supabase"."option_sets" y where y."id" = v_set);
end;
$$;
revoke execute on function "better_supabase"."ensure_option_set"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."ensure_option_set"(uuid, text, text, text) to authenticated, service_role;

-- Creates an option set (option_set null) or renames one. Returns it with its
-- items. A set made the default replaces the field's previous default.
create or replace function "better_supabase"."save_option_set"(tenant uuid, option_set uuid, subject_type text, field text, key text, name text, scope_id text default null, is_default boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_set uuid := save_option_set.option_set;
  v_tenant uuid := save_option_set.tenant;
  v_type text := save_option_set.subject_type;
  v_field text := save_option_set.field;
  v_created boolean := save_option_set.option_set is null;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_option_set.tenant, 'option_sets.manage'), false)) then
    raise exception 'not allowed to manage option sets' using errcode = '42501', hint = 'OPTION_SET_FORBIDDEN';
  end if;
  if not (save_option_set.subject_type || '.' || save_option_set.field = any ('{work_item.priority}'::text[])) then
    raise exception 'this field has no option set binding' using errcode = '22023', hint = 'OPTION_SET_FIELD_UNKNOWN';
  end if;
  if coalesce(save_option_set.is_default, false) then
    update "better_supabase"."option_sets" x set "is_default" = false
    where x."tenant_id" = save_option_set.tenant and x."subject_type" = save_option_set.subject_type
      and x."field" = save_option_set.field
      and x."scope_id" is not distinct from save_option_set.scope_id and x."is_default"
      and x."id" is distinct from save_option_set.option_set;
  end if;
  begin
    if v_created then
      insert into "better_supabase"."option_sets" ("tenant_id", "subject_type", "field", "scope_id", "key", "name", "is_default")
      values (save_option_set.tenant, save_option_set.subject_type, save_option_set.field, save_option_set.scope_id, save_option_set.key, save_option_set.name,
        coalesce(save_option_set.is_default, false) or not exists (
          select 1 from "better_supabase"."option_sets" x where x."tenant_id" = save_option_set.tenant and x."subject_type" = save_option_set.subject_type
            and x."field" = save_option_set.field
            and x."scope_id" is not distinct from save_option_set.scope_id and x."archived_at" is null))
      returning "id" into v_set;
    else
      update "better_supabase"."option_sets" x set "key" = save_option_set.key, "name" = save_option_set.name,
        "is_default" = coalesce(save_option_set.is_default, x."is_default"), "updated_at" = now()
      where x."id" = save_option_set.option_set and x."tenant_id" = save_option_set.tenant
        and x."subject_type" = save_option_set.subject_type and x."field" = save_option_set.field;
      if not found then
        raise exception 'option set not found' using errcode = 'P0002', hint = 'OPTION_SET_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another option set of this field has this key' using errcode = '23505', hint = 'OPTION_SET_KEY_TAKEN';
  end;
  if v_created then
    perform "better_supabase".emit_event('option_set.created', jsonb_build_object('organizationId', v_tenant, 'optionSetId', v_set, 'subjectType', v_type, 'field', v_field, 'key', save_option_set.key), 'option-sets/' || v_set::text, (v_tenant::text)::text, null, 'better-supabase/option-sets');
  perform better_supabase.audit_event(
    event_type => 'option_set.created',
    category => 'configuration',
    target_type => 'option_set',
    record_id => v_set::text,
    summary => 'created option set ' || save_option_set.name,
    tenant => (v_tenant::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'optionSetId', v_set, 'subjectType', v_type, 'field', v_field, 'key', save_option_set.key)
  );
  else
    perform "better_supabase".emit_event('option_set.updated', jsonb_build_object('organizationId', v_tenant, 'optionSetId', v_set, 'subjectType', v_type, 'field', v_field, 'key', save_option_set.key), 'option-sets/' || v_set::text, (v_tenant::text)::text, null, 'better-supabase/option-sets');
  perform better_supabase.audit_event(
    event_type => 'option_set.updated',
    category => 'configuration',
    target_type => 'option_set',
    record_id => v_set::text,
    summary => 'updated option set ' || save_option_set.name,
    tenant => (v_tenant::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'optionSetId', v_set, 'subjectType', v_type, 'field', v_field, 'key', save_option_set.key)
  );
  end if;
  return (select to_jsonb(y) || jsonb_build_object('items', coalesce((
      select jsonb_agg(to_jsonb(z) order by z."rank" collate "C", z."id")
      from "better_supabase"."option_set_items" z
      where z."option_set_id" = y."id" and (false or z."archived_at" is null)
    ), '[]'::jsonb)) from "better_supabase"."option_sets" y where y."id" = v_set);
end;
$$;
revoke execute on function "better_supabase"."save_option_set"(uuid, uuid, text, text, text, text, text, boolean) from public, anon;
grant execute on function "better_supabase"."save_option_set"(uuid, uuid, text, text, text, text, text, boolean) to authenticated, service_role;

-- Creates an item at the end of a set (item null) or changes one. The level
-- must lie within the bounds of the field's binding; records on the item take
-- the new level.
create or replace function "better_supabase"."save_option_set_item"(option_set uuid, item uuid, key text, label text, level integer, color text default null, icon text default null, description text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_type text;
  v_field text;
  v_min integer;
  v_max integer;
  v_set uuid := save_option_set_item.option_set;
  v_item uuid := save_option_set_item.item;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."subject_type", x."field" into v_tenant, v_type, v_field
  from "better_supabase"."option_sets" x where x."id" = save_option_set_item.option_set and x."archived_at" is null;
  if v_tenant is null then
    raise exception 'option set not found' using errcode = 'P0002', hint = 'OPTION_SET_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'option_sets.manage'), false)) then
    raise exception 'not allowed to manage option sets' using errcode = '42501', hint = 'OPTION_SET_FORBIDDEN';
  end if;
      if v_type = 'work_item' and v_field = 'priority' then
      v_min := 0;
      v_max := 4;
    else
      raise exception 'this field has no option set binding' using errcode = '22023', hint = 'OPTION_SET_FIELD_UNKNOWN';
    end if;
  if save_option_set_item.level is null or save_option_set_item.level < v_min or save_option_set_item.level > v_max then
    raise exception 'the level is outside the bounds of this field' using errcode = '22023', hint = 'OPTION_SET_LEVEL_INVALID';
  end if;
  begin
    if v_item is null then
      insert into "better_supabase"."option_set_items" ("tenant_id", "option_set_id", "key", "label", "level", "color", "icon", "description", "rank")
      values (v_tenant, save_option_set_item.option_set, save_option_set_item.key, save_option_set_item.label, save_option_set_item.level,
        save_option_set_item.color, save_option_set_item.icon, save_option_set_item.description,
        case
    when (select max(x."rank" collate "C") from "better_supabase"."option_set_items" x where x."option_set_id" = save_option_set_item.option_set) is null then 'V'
    when length(substring((select max(x."rank" collate "C") from "better_supabase"."option_set_items" x where x."option_set_id" = save_option_set_item.option_set) from '^z*')) = length((select max(x."rank" collate "C") from "better_supabase"."option_set_items" x where x."option_set_id" = save_option_set_item.option_set)) then (select max(x."rank" collate "C") from "better_supabase"."option_set_items" x where x."option_set_id" = save_option_set_item.option_set) || 'V'
    else left((select max(x."rank" collate "C") from "better_supabase"."option_set_items" x where x."option_set_id" = save_option_set_item.option_set), length(substring((select max(x."rank" collate "C") from "better_supabase"."option_set_items" x where x."option_set_id" = save_option_set_item.option_set) from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr((select max(x."rank" collate "C") from "better_supabase"."option_set_items" x where x."option_set_id" = save_option_set_item.option_set), length(substring((select max(x."rank" collate "C") from "better_supabase"."option_set_items" x where x."option_set_id" = save_option_set_item.option_set) from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end)
      returning "id" into v_item;
    else
      update "better_supabase"."option_set_items" x set "key" = save_option_set_item.key, "label" = save_option_set_item.label,
        "level" = save_option_set_item.level, "color" = save_option_set_item.color, "icon" = save_option_set_item.icon,
        "description" = save_option_set_item.description, "updated_at" = now()
      where x."id" = v_item and x."option_set_id" = save_option_set_item.option_set;
      if not found then
        raise exception 'item not found' using errcode = 'P0002', hint = 'OPTION_SET_ITEM_NOT_FOUND';
      end if;
          if v_type = 'work_item' and v_field = 'priority' then
      update "better_supabase"."work_items" r set "priority" = save_option_set_item.level
      where r."priority_option_id" = v_item;
    else
      null;
    end if;
    end if;
  exception when unique_violation then
    raise exception 'another item of this set has this key' using errcode = '23505', hint = 'OPTION_SET_ITEM_KEY_TAKEN';
  end;
  if save_option_set_item.item is null then
    perform "better_supabase".emit_event('option_set_item.created', jsonb_build_object('organizationId', v_tenant, 'optionSetId', v_set, 'itemId', v_item, 'key', save_option_set_item.key, 'level', save_option_set_item.level), 'option-sets/' || v_set::text, (v_tenant::text)::text, null, 'better-supabase/option-sets');
  perform better_supabase.audit_event(
    event_type => 'option_set_item.created',
    category => 'configuration',
    target_type => 'option_set_item',
    record_id => v_item::text,
    summary => 'created option set item ' || save_option_set_item.label,
    tenant => (v_tenant::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'optionSetId', v_set, 'itemId', v_item, 'key', save_option_set_item.key, 'level', save_option_set_item.level)
  );
  else
    perform "better_supabase".emit_event('option_set_item.updated', jsonb_build_object('organizationId', v_tenant, 'optionSetId', v_set, 'itemId', v_item, 'key', save_option_set_item.key, 'level', save_option_set_item.level), 'option-sets/' || v_set::text, (v_tenant::text)::text, null, 'better-supabase/option-sets');
  perform better_supabase.audit_event(
    event_type => 'option_set_item.updated',
    category => 'configuration',
    target_type => 'option_set_item',
    record_id => v_item::text,
    summary => 'updated option set item ' || save_option_set_item.label,
    tenant => (v_tenant::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'optionSetId', v_set, 'itemId', v_item, 'key', save_option_set_item.key, 'level', save_option_set_item.level)
  );
  end if;
  return (select to_jsonb(x) from "better_supabase"."option_set_items" x where x."id" = v_item);
end;
$$;
revoke execute on function "better_supabase"."save_option_set_item"(uuid, uuid, text, text, integer, text, text, text) from public, anon;
grant execute on function "better_supabase"."save_option_set_item"(uuid, uuid, text, text, integer, text, text, text) to authenticated, service_role;

-- Moves an item to a rank key the client computed with rankBetween.
create or replace function "better_supabase"."rank_option_set_item"(item uuid, rank text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."option_set_items" x where x."id" = rank_option_set_item.item;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'option_sets.manage'), false)) then
    raise exception 'not allowed to manage option sets' using errcode = '42501', hint = 'OPTION_SET_FORBIDDEN';
  end if;
  if rank_option_set_item.rank is null or rank_option_set_item.rank !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'not a rank key' using errcode = '22023', hint = 'OPTION_SET_RANK_INVALID';
  end if;
  update "better_supabase"."option_set_items" x set "rank" = rank_option_set_item.rank, "updated_at" = now()
  where x."id" = rank_option_set_item.item;
  return true;
end;
$$;
revoke execute on function "better_supabase"."rank_option_set_item"(uuid, text) from public, anon;
grant execute on function "better_supabase"."rank_option_set_item"(uuid, text) to authenticated, service_role;

-- Archives an item. Records on it must move first: pass replacement, an active
-- item of the same set, to move them in the same call. A set keeps at least
-- one active item.
create or replace function "better_supabase"."archive_option_set_item"(item uuid, replacement uuid default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_set uuid;
  v_type text;
  v_field text;
  v_used boolean;
  v_item uuid := archive_option_set_item.item;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."option_set_id", y."subject_type", y."field" into v_tenant, v_set, v_type, v_field
  from "better_supabase"."option_set_items" x join "better_supabase"."option_sets" y on y."id" = x."option_set_id"
  where x."id" = archive_option_set_item.item and x."archived_at" is null;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'option_sets.manage'), false)) then
    raise exception 'not allowed to manage option sets' using errcode = '42501', hint = 'OPTION_SET_FORBIDDEN';
  end if;
  if archive_option_set_item.replacement is not null and not exists (
    select 1 from "better_supabase"."option_set_items" x
    where x."id" = archive_option_set_item.replacement and x."option_set_id" = v_set
      and x."archived_at" is null and x."id" <> archive_option_set_item.item
  ) then
    raise exception 'the replacement must be another active item of the same set' using errcode = '22023', hint = 'OPTION_SET_REPLACEMENT_INVALID';
  end if;
  if not exists (
    select 1 from "better_supabase"."option_set_items" x
    where x."option_set_id" = v_set and x."archived_at" is null and x."id" <> archive_option_set_item.item
  ) then
    raise exception 'an option set keeps at least one item' using errcode = '23514', hint = 'OPTION_SET_LAST_ITEM';
  end if;
      if v_type = 'work_item' and v_field = 'priority' then
      perform 1 from "better_supabase"."work_items" r where r."priority_option_id" = archive_option_set_item.item limit 1;
      v_used := found;
    else
      v_used := false;
    end if;
  if v_used then
    if archive_option_set_item.replacement is null then
      raise exception 'records use this item; pass a replacement' using errcode = '23503', hint = 'OPTION_SET_ITEM_IN_USE';
    end if;
        if v_type = 'work_item' and v_field = 'priority' then
      update "better_supabase"."work_items" r set "priority_option_id" = archive_option_set_item.replacement
      where r."priority_option_id" = archive_option_set_item.item;
    else
      null;
    end if;
  end if;
  update "better_supabase"."option_set_items" x set "archived_at" = now(), "updated_at" = now() where x."id" = archive_option_set_item.item;
  perform "better_supabase".emit_event('option_set_item.archived', jsonb_build_object('organizationId', v_tenant, 'optionSetId', v_set, 'itemId', v_item), 'option-sets/' || v_set::text, (v_tenant::text)::text, null, 'better-supabase/option-sets');
  perform better_supabase.audit_event(
    event_type => 'option_set_item.archived',
    category => 'configuration',
    target_type => 'option_set_item',
    record_id => v_item::text,
    summary => 'archived an option set item',
    tenant => (v_tenant::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'optionSetId', v_set, 'itemId', v_item)
  );
  return true;
end;
$$;
revoke execute on function "better_supabase"."archive_option_set_item"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."archive_option_set_item"(uuid, uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."option_sets" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('option_sets.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."option_sets" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."option_sets" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."option_sets" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."option_set_items" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('option_sets.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."option_set_items" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."option_set_items" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."option_set_items" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- Row audit for the module's tables (blocks.audit.options.blockTables)
create constraint trigger bsb_audit after insert or update or delete on better_supabase.option_sets deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"option_set","event_prefix":"option_set"}');

-- blocks.option-sets.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."default_option_set"(tenant uuid, subject_type text, field text, scope_id text)
returns uuid
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."default_option_set"($1, $2, $3, $4) $$;
revoke execute on function "api"."default_option_set"(uuid, text, text, text) from public, anon, authenticated;
grant execute on function "api"."default_option_set"(uuid, text, text, text) to service_role;

create or replace function "api"."list_option_sets"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_option_sets"($1, $2) $$;
revoke execute on function "api"."list_option_sets"(uuid, jsonb) from public, anon;
grant execute on function "api"."list_option_sets"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."ensure_option_set"(tenant uuid, subject_type text, field text, scope_id text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."ensure_option_set"($1, $2, $3, $4) $$;
revoke execute on function "api"."ensure_option_set"(uuid, text, text, text) from public, anon;
grant execute on function "api"."ensure_option_set"(uuid, text, text, text) to authenticated, service_role;

create or replace function "api"."save_option_set"(tenant uuid, option_set uuid, subject_type text, field text, key text, name text, scope_id text default null, is_default boolean default false)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_option_set"($1, $2, $3, $4, $5, $6, $7, $8) $$;
revoke execute on function "api"."save_option_set"(uuid, uuid, text, text, text, text, text, boolean) from public, anon;
grant execute on function "api"."save_option_set"(uuid, uuid, text, text, text, text, text, boolean) to authenticated, service_role;

create or replace function "api"."save_option_set_item"(option_set uuid, item uuid, key text, label text, level integer, color text default null, icon text default null, description text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_option_set_item"($1, $2, $3, $4, $5, $6, $7, $8) $$;
revoke execute on function "api"."save_option_set_item"(uuid, uuid, text, text, integer, text, text, text) from public, anon;
grant execute on function "api"."save_option_set_item"(uuid, uuid, text, text, integer, text, text, text) to authenticated, service_role;

create or replace function "api"."rank_option_set_item"(item uuid, rank text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."rank_option_set_item"($1, $2) $$;
revoke execute on function "api"."rank_option_set_item"(uuid, text) from public, anon;
grant execute on function "api"."rank_option_set_item"(uuid, text) to authenticated, service_role;

create or replace function "api"."archive_option_set_item"(item uuid, replacement uuid default null)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."archive_option_set_item"($1, $2) $$;
revoke execute on function "api"."archive_option_set_item"(uuid, uuid) from public, anon;
grant execute on function "api"."archive_option_set_item"(uuid, uuid) to authenticated, service_role;
