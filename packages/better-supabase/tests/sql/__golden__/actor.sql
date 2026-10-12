-- ==== alone: schema supabase/schemas/900_better_supabase_02_actor.sql
-- better-supabase module: actor
-- @bs-module actor@1 managed
-- Sets created_by on insert and updated_by on every write from auth.uid(); an update keeps created_by and the impersonation stamp. Service writes keep the values they send.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

create or replace function better_supabase.set_actor()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  actor uuid := auth.uid();
begin
  if actor is null then
    return new;
  end if;
  if tg_argv[0] <> '' then
    new := jsonb_populate_record(new, jsonb_build_object(
      tg_argv[0],
      case when tg_op = 'INSERT' then to_jsonb(actor) else to_jsonb(old) -> tg_argv[0] end
    ));
  end if;
  if tg_argv[1] = 'updated_by' then
    new.updated_by := actor;
  elsif tg_argv[1] <> '' then
    new := jsonb_populate_record(new, jsonb_build_object(tg_argv[1], actor));
  end if;
  -- The admin behind an impersonated write (the act claim). A user's own
  -- update keeps the stamp, so it cannot clear the record of an earlier one.
  if tg_nargs > 2 and tg_argv[2] <> '' then
    new := jsonb_populate_record(new, jsonb_build_object(
      tg_argv[2],
      case
        when auth.jwt() -> 'act' ->> 'sub' is not null then to_jsonb(auth.jwt() -> 'act' ->> 'sub')
        when tg_op = 'INSERT' then 'null'::jsonb
        else to_jsonb(old) -> tg_argv[2]
      end
    ));
  end if;
  return new;
end;
$$;

drop function if exists better_supabase.track_actor(regclass, text, text);

-- select better_supabase.track_actor('public.customers');
-- impersonated_by => 'impersonated_by' also stamps the impersonating admin.
create or replace function better_supabase.track_actor(
  target regclass,
  created_by text default 'created_by',
  updated_by text default 'updated_by',
  impersonated_by text default null
)
returns void
language plpgsql
set search_path = ''
as $$
begin
  execute format('drop trigger if exists bs_actor on %s', target);
  execute format(
    'create trigger bs_actor before insert or update on %s for each row execute function better_supabase.set_actor(%L, %L, %L)',
    target,
    coalesce(created_by, ''),
    coalesce(updated_by, ''),
    coalesce(impersonated_by, '')
  );
end;
$$;

revoke execute on function better_supabase.track_actor(regclass, text, text, text) from public, anon, authenticated;

create schema if not exists better_supabase;
create table if not exists better_supabase.modules (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.modules enable row level security;
revoke all on better_supabase.modules from anon, authenticated;
grant select on better_supabase.modules to service_role;

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_02_actor.sql
-- better-supabase module: actor
-- @bs-module-data actor
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('actor', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_02_actor.sql
-- better-supabase module: actor
-- @bs-module actor@1 managed
-- Sets created_by on insert and updated_by on every write from auth.uid(); an update keeps created_by and the impersonation stamp. Service writes keep the values they send.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

create or replace function better_supabase.set_actor()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  actor uuid := auth.uid();
begin
  if actor is null then
    return new;
  end if;
  if tg_argv[0] <> '' then
    new := jsonb_populate_record(new, jsonb_build_object(
      tg_argv[0],
      case when tg_op = 'INSERT' then to_jsonb(actor) else to_jsonb(old) -> tg_argv[0] end
    ));
  end if;
  if tg_argv[1] = 'updated_by' then
    new.updated_by := actor;
  elsif tg_argv[1] <> '' then
    new := jsonb_populate_record(new, jsonb_build_object(tg_argv[1], actor));
  end if;
  -- The admin behind an impersonated write (the act claim). A user's own
  -- update keeps the stamp, so it cannot clear the record of an earlier one.
  if tg_nargs > 2 and tg_argv[2] <> '' then
    new := jsonb_populate_record(new, jsonb_build_object(
      tg_argv[2],
      case
        when auth.jwt() -> 'act' ->> 'sub' is not null then to_jsonb(auth.jwt() -> 'act' ->> 'sub')
        when tg_op = 'INSERT' then 'null'::jsonb
        else to_jsonb(old) -> tg_argv[2]
      end
    ));
  end if;
  return new;
end;
$$;

drop function if exists better_supabase.track_actor(regclass, text, text);

-- select better_supabase.track_actor('public.customers');
-- impersonated_by => 'impersonated_by' also stamps the impersonating admin.
create or replace function better_supabase.track_actor(
  target regclass,
  created_by text default 'created_by',
  updated_by text default 'updated_by',
  impersonated_by text default null
)
returns void
language plpgsql
set search_path = ''
as $$
begin
  execute format('drop trigger if exists bs_actor on %s', target);
  execute format(
    'create trigger bs_actor before insert or update on %s for each row execute function better_supabase.set_actor(%L, %L, %L)',
    target,
    coalesce(created_by, ''),
    coalesce(updated_by, ''),
    coalesce(impersonated_by, '')
  );
end;
$$;

revoke execute on function better_supabase.track_actor(regclass, text, text, text) from public, anon, authenticated;

create schema if not exists better_supabase;
create table if not exists better_supabase.modules (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.modules enable row level security;
revoke all on better_supabase.modules from anon, authenticated;
grant select on better_supabase.modules to service_role;

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_02_actor.sql
-- better-supabase module: actor
-- @bs-module-data actor
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('actor', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_02_actor.sql
-- better-supabase module: actor
-- @bs-module actor@1 managed
-- Sets created_by on insert and updated_by on every write from auth.uid(); an update keeps created_by and the impersonation stamp. Service writes keep the values they send.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

create or replace function better_supabase.set_actor()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  actor uuid := auth.uid();
begin
  if actor is null then
    return new;
  end if;
  if tg_argv[0] <> '' then
    new := jsonb_populate_record(new, jsonb_build_object(
      tg_argv[0],
      case when tg_op = 'INSERT' then to_jsonb(actor) else to_jsonb(old) -> tg_argv[0] end
    ));
  end if;
  if tg_argv[1] = 'updated_by' then
    new.updated_by := actor;
  elsif tg_argv[1] <> '' then
    new := jsonb_populate_record(new, jsonb_build_object(tg_argv[1], actor));
  end if;
  -- The admin behind an impersonated write (the act claim). A user's own
  -- update keeps the stamp, so it cannot clear the record of an earlier one.
  if tg_nargs > 2 and tg_argv[2] <> '' then
    new := jsonb_populate_record(new, jsonb_build_object(
      tg_argv[2],
      case
        when auth.jwt() -> 'act' ->> 'sub' is not null then to_jsonb(auth.jwt() -> 'act' ->> 'sub')
        when tg_op = 'INSERT' then 'null'::jsonb
        else to_jsonb(old) -> tg_argv[2]
      end
    ));
  end if;
  return new;
end;
$$;

drop function if exists better_supabase.track_actor(regclass, text, text);

-- select better_supabase.track_actor('public.customers');
-- impersonated_by => 'impersonated_by' also stamps the impersonating admin.
create or replace function better_supabase.track_actor(
  target regclass,
  created_by text default 'created_by',
  updated_by text default 'updated_by',
  impersonated_by text default null
)
returns void
language plpgsql
set search_path = ''
as $$
begin
  execute format('drop trigger if exists bs_actor on %s', target);
  execute format(
    'create trigger bs_actor before insert or update on %s for each row execute function better_supabase.set_actor(%L, %L, %L)',
    target,
    coalesce(created_by, ''),
    coalesce(updated_by, ''),
    coalesce(impersonated_by, '')
  );
end;
$$;

revoke execute on function better_supabase.track_actor(regclass, text, text, text) from public, anon, authenticated;

create schema if not exists better_supabase;
create table if not exists better_supabase.modules (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.modules enable row level security;
revoke all on better_supabase.modules from anon, authenticated;
grant select on better_supabase.modules to service_role;

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_02_actor.sql
-- better-supabase module: actor
-- @bs-module-data actor
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('actor', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_02_actor.sql
-- better-supabase module: actor
-- @bs-module actor@1 managed
-- Sets created_by on insert and updated_by on every write from auth.uid(); an update keeps created_by and the impersonation stamp. Service writes keep the values they send.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

create or replace function better_supabase.set_actor()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  actor uuid := auth.uid();
begin
  if actor is null then
    return new;
  end if;
  if tg_argv[0] <> '' then
    new := jsonb_populate_record(new, jsonb_build_object(
      tg_argv[0],
      case when tg_op = 'INSERT' then to_jsonb(actor) else to_jsonb(old) -> tg_argv[0] end
    ));
  end if;
  if tg_argv[1] = 'updated_by' then
    new.updated_by := actor;
  elsif tg_argv[1] <> '' then
    new := jsonb_populate_record(new, jsonb_build_object(tg_argv[1], actor));
  end if;
  -- The admin behind an impersonated write (the act claim). A user's own
  -- update keeps the stamp, so it cannot clear the record of an earlier one.
  if tg_nargs > 2 and tg_argv[2] <> '' then
    new := jsonb_populate_record(new, jsonb_build_object(
      tg_argv[2],
      case
        when auth.jwt() -> 'act' ->> 'sub' is not null then to_jsonb(auth.jwt() -> 'act' ->> 'sub')
        when tg_op = 'INSERT' then 'null'::jsonb
        else to_jsonb(old) -> tg_argv[2]
      end
    ));
  end if;
  return new;
end;
$$;

drop function if exists better_supabase.track_actor(regclass, text, text);

-- select better_supabase.track_actor('public.customers');
-- impersonated_by => 'impersonated_by' also stamps the impersonating admin.
create or replace function better_supabase.track_actor(
  target regclass,
  created_by text default 'created_by',
  updated_by text default 'updated_by',
  impersonated_by text default null
)
returns void
language plpgsql
set search_path = ''
as $$
begin
  execute format('drop trigger if exists bs_actor on %s', target);
  execute format(
    'create trigger bs_actor before insert or update on %s for each row execute function better_supabase.set_actor(%L, %L, %L)',
    target,
    coalesce(created_by, ''),
    coalesce(updated_by, ''),
    coalesce(impersonated_by, '')
  );
end;
$$;

revoke execute on function better_supabase.track_actor(regclass, text, text, text) from public, anon, authenticated;

create schema if not exists better_supabase;
create table if not exists better_supabase.modules (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.modules enable row level security;
revoke all on better_supabase.modules from anon, authenticated;
grant select on better_supabase.modules to service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_02_actor.sql
-- better-supabase module: actor
-- @bs-module-data actor
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('actor', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
