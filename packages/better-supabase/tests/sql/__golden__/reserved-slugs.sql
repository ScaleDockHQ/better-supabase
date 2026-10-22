-- ==== alone: schema supabase/schemas/900_better_supabase_06_reserved_slugs.sql
-- better-supabase module: reserved-slugs
-- @bsb-block reserved-slugs@1 managed
-- A slug format and length check and a list of reserved words (admin, api, www, ...), enforced by a trigger.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

create table if not exists better_supabase.reserved_slugs (
  slug text primary key,
  reason text
);
alter table better_supabase.reserved_slugs enable row level security;
-- enforce_slug runs as the writer, service_role included, and reads this list.
grant select on better_supabase.reserved_slugs to anon, authenticated, service_role;
drop policy if exists bsb_reserved_slugs_read on better_supabase.reserved_slugs;
create policy bsb_reserved_slugs_read on better_supabase.reserved_slugs for select to anon, authenticated, service_role using (true);

-- 'invalid' for a malformed slug or one outside 1 to 63 characters
-- (blocks.reserved-slugs.options.minLength and maxLength), 'reserved', or null.
create or replace function better_supabase.slug_problem(slug text)
returns text
language sql
stable
set search_path = ''
as $$
  select case
    when slug is null then null
    when slug !~ '^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$' then 'invalid'
    when slug ~ '--' then 'invalid'
    when length(slug) < 1 or length(slug) > 63 then 'invalid'
    when exists (select 1 from better_supabase.reserved_slugs r where r.slug = slug_problem.slug) then 'reserved'
  end
$$;

create or replace function better_supabase.enforce_slug()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  value text := to_jsonb(new) ->> coalesce(tg_argv[0], 'slug');
  problem text := better_supabase.slug_problem(value);
begin
  if problem = 'invalid' then
    raise exception 'Invalid slug "%"', value using errcode = '23514', hint = 'SLUG_INVALID';
  elsif problem = 'reserved' then
    raise exception 'The slug "%" is reserved', value using errcode = '23514', hint = 'SLUG_RESERVED';
  end if;
  return new;
end;
$$;

-- select better_supabase.track_slug('public.organizations');
create or replace function better_supabase.track_slug(target regclass, column_name text default 'slug')
returns void
language plpgsql
set search_path = ''
as $$
begin
  execute format('drop trigger if exists bsb_slug on %s', target);
  execute format(
    'create trigger bsb_slug before insert or update of %I on %s for each row execute function better_supabase.enforce_slug(%L)',
    column_name,
    target,
    column_name
  );
end;
$$;

-- enforce_slug runs as the writer, so the check stays callable by authenticated.
revoke execute on function better_supabase.slug_problem(text) from public, anon;
grant execute on function better_supabase.slug_problem(text) to authenticated, service_role;
revoke execute on function better_supabase.track_slug(regclass, text) from public, anon, authenticated;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_06_reserved_slugs.sql
-- better-supabase module: reserved-slugs
-- @bsb-block-data reserved-slugs
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.reserved_slugs (slug, reason)
select value, 'system'
from unnest(array[
  'about', 'account', 'admin', 'api', 'app', 'assets', 'auth', 'billing', 'blog',
  'callback', 'cdn', 'dashboard', 'docs', 'help', 'invite', 'login', 'logout',
  'mail', 'new', 'oauth', 'onboarding', 'pricing', 'privacy', 'root', 'settings',
  'signin', 'signout', 'signup', 'static', 'status', 'support', 'system', 'terms',
  'www'
]) as value
on conflict (slug) do nothing;

insert into better_supabase.blocks (name, version, mode)
values ('reserved-slugs', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_06_reserved_slugs.sql
-- better-supabase module: reserved-slugs
-- @bsb-block reserved-slugs@1 managed
-- A slug format and length check and a list of reserved words (admin, api, www, ...), enforced by a trigger.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

create table if not exists better_supabase.reserved_slugs (
  slug text primary key,
  reason text
);
alter table better_supabase.reserved_slugs enable row level security;
-- enforce_slug runs as the writer, service_role included, and reads this list.
grant select on better_supabase.reserved_slugs to anon, authenticated, service_role;
drop policy if exists bsb_reserved_slugs_read on better_supabase.reserved_slugs;
create policy bsb_reserved_slugs_read on better_supabase.reserved_slugs for select to anon, authenticated, service_role using (true);

-- 'invalid' for a malformed slug or one outside 1 to 63 characters
-- (blocks.reserved-slugs.options.minLength and maxLength), 'reserved', or null.
create or replace function better_supabase.slug_problem(slug text)
returns text
language sql
stable
set search_path = ''
as $$
  select case
    when slug is null then null
    when slug !~ '^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$' then 'invalid'
    when slug ~ '--' then 'invalid'
    when length(slug) < 1 or length(slug) > 63 then 'invalid'
    when exists (select 1 from better_supabase.reserved_slugs r where r.slug = slug_problem.slug) then 'reserved'
  end
$$;

create or replace function better_supabase.enforce_slug()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  value text := to_jsonb(new) ->> coalesce(tg_argv[0], 'slug');
  problem text := better_supabase.slug_problem(value);
begin
  if problem = 'invalid' then
    raise exception 'Invalid slug "%"', value using errcode = '23514', hint = 'SLUG_INVALID';
  elsif problem = 'reserved' then
    raise exception 'The slug "%" is reserved', value using errcode = '23514', hint = 'SLUG_RESERVED';
  end if;
  return new;
end;
$$;

-- select better_supabase.track_slug('public.organizations');
create or replace function better_supabase.track_slug(target regclass, column_name text default 'slug')
returns void
language plpgsql
set search_path = ''
as $$
begin
  execute format('drop trigger if exists bsb_slug on %s', target);
  execute format(
    'create trigger bsb_slug before insert or update of %I on %s for each row execute function better_supabase.enforce_slug(%L)',
    column_name,
    target,
    column_name
  );
end;
$$;

-- enforce_slug runs as the writer, so the check stays callable by authenticated.
revoke execute on function better_supabase.slug_problem(text) from public, anon;
grant execute on function better_supabase.slug_problem(text) to authenticated, service_role;
revoke execute on function better_supabase.track_slug(regclass, text) from public, anon, authenticated;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_06_reserved_slugs.sql
-- better-supabase module: reserved-slugs
-- @bsb-block-data reserved-slugs
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.reserved_slugs (slug, reason)
select value, 'system'
from unnest(array[
  'about', 'account', 'admin', 'api', 'app', 'assets', 'auth', 'billing', 'blog',
  'callback', 'cdn', 'dashboard', 'docs', 'help', 'invite', 'login', 'logout',
  'mail', 'new', 'oauth', 'onboarding', 'pricing', 'privacy', 'root', 'settings',
  'signin', 'signout', 'signup', 'static', 'status', 'support', 'system', 'terms',
  'www'
]) as value
on conflict (slug) do nothing;

insert into better_supabase.blocks (name, version, mode)
values ('reserved-slugs', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_06_reserved_slugs.sql
-- better-supabase module: reserved-slugs
-- @bsb-block reserved-slugs@1 managed
-- A slug format and length check and a list of reserved words (admin, api, www, ...), enforced by a trigger.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

create table if not exists better_supabase.reserved_slugs (
  slug text primary key,
  reason text
);
alter table better_supabase.reserved_slugs enable row level security;
-- enforce_slug runs as the writer, service_role included, and reads this list.
grant select on better_supabase.reserved_slugs to anon, authenticated, service_role;
drop policy if exists bsb_reserved_slugs_read on better_supabase.reserved_slugs;
create policy bsb_reserved_slugs_read on better_supabase.reserved_slugs for select to anon, authenticated, service_role using (true);

-- 'invalid' for a malformed slug or one outside 1 to 63 characters
-- (blocks.reserved-slugs.options.minLength and maxLength), 'reserved', or null.
create or replace function better_supabase.slug_problem(slug text)
returns text
language sql
stable
set search_path = ''
as $$
  select case
    when slug is null then null
    when slug !~ '^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$' then 'invalid'
    when slug ~ '--' then 'invalid'
    when length(slug) < 1 or length(slug) > 63 then 'invalid'
    when exists (select 1 from better_supabase.reserved_slugs r where r.slug = slug_problem.slug) then 'reserved'
  end
$$;

create or replace function better_supabase.enforce_slug()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  value text := to_jsonb(new) ->> coalesce(tg_argv[0], 'slug');
  problem text := better_supabase.slug_problem(value);
begin
  if problem = 'invalid' then
    raise exception 'Invalid slug "%"', value using errcode = '23514', hint = 'SLUG_INVALID';
  elsif problem = 'reserved' then
    raise exception 'The slug "%" is reserved', value using errcode = '23514', hint = 'SLUG_RESERVED';
  end if;
  return new;
end;
$$;

-- select better_supabase.track_slug('public.organizations');
create or replace function better_supabase.track_slug(target regclass, column_name text default 'slug')
returns void
language plpgsql
set search_path = ''
as $$
begin
  execute format('drop trigger if exists bsb_slug on %s', target);
  execute format(
    'create trigger bsb_slug before insert or update of %I on %s for each row execute function better_supabase.enforce_slug(%L)',
    column_name,
    target,
    column_name
  );
end;
$$;

-- enforce_slug runs as the writer, so the check stays callable by authenticated.
revoke execute on function better_supabase.slug_problem(text) from public, anon;
grant execute on function better_supabase.slug_problem(text) to authenticated, service_role;
revoke execute on function better_supabase.track_slug(regclass, text) from public, anon, authenticated;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_06_reserved_slugs.sql
-- better-supabase module: reserved-slugs
-- @bsb-block-data reserved-slugs
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.reserved_slugs (slug, reason)
select value, 'system'
from unnest(array[
  'about', 'account', 'admin', 'api', 'app', 'assets', 'auth', 'billing', 'blog',
  'callback', 'cdn', 'dashboard', 'docs', 'help', 'invite', 'login', 'logout',
  'mail', 'new', 'oauth', 'onboarding', 'pricing', 'privacy', 'root', 'settings',
  'signin', 'signout', 'signup', 'static', 'status', 'support', 'system', 'terms',
  'www'
]) as value
on conflict (slug) do nothing;

insert into better_supabase.blocks (name, version, mode)
values ('reserved-slugs', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_06_reserved_slugs.sql
-- better-supabase module: reserved-slugs
-- @bsb-block reserved-slugs@1 managed
-- A slug format and length check and a list of reserved words (admin, api, www, ...), enforced by a trigger.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

create table if not exists better_supabase.reserved_slugs (
  slug text primary key,
  reason text
);
alter table better_supabase.reserved_slugs enable row level security;
-- enforce_slug runs as the writer, service_role included, and reads this list.
grant select on better_supabase.reserved_slugs to anon, authenticated, service_role;
drop policy if exists bsb_reserved_slugs_read on better_supabase.reserved_slugs;
create policy bsb_reserved_slugs_read on better_supabase.reserved_slugs for select to anon, authenticated, service_role using (true);

-- 'invalid' for a malformed slug or one outside 1 to 63 characters
-- (blocks.reserved-slugs.options.minLength and maxLength), 'reserved', or null.
create or replace function better_supabase.slug_problem(slug text)
returns text
language sql
stable
set search_path = ''
as $$
  select case
    when slug is null then null
    when slug !~ '^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$' then 'invalid'
    when slug ~ '--' then 'invalid'
    when length(slug) < 1 or length(slug) > 63 then 'invalid'
    when exists (select 1 from better_supabase.reserved_slugs r where r.slug = slug_problem.slug) then 'reserved'
  end
$$;

create or replace function better_supabase.enforce_slug()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  value text := to_jsonb(new) ->> coalesce(tg_argv[0], 'slug');
  problem text := better_supabase.slug_problem(value);
begin
  if problem = 'invalid' then
    raise exception 'Invalid slug "%"', value using errcode = '23514', hint = 'SLUG_INVALID';
  elsif problem = 'reserved' then
    raise exception 'The slug "%" is reserved', value using errcode = '23514', hint = 'SLUG_RESERVED';
  end if;
  return new;
end;
$$;

-- select better_supabase.track_slug('public.organizations');
create or replace function better_supabase.track_slug(target regclass, column_name text default 'slug')
returns void
language plpgsql
set search_path = ''
as $$
begin
  execute format('drop trigger if exists bsb_slug on %s', target);
  execute format(
    'create trigger bsb_slug before insert or update of %I on %s for each row execute function better_supabase.enforce_slug(%L)',
    column_name,
    target,
    column_name
  );
end;
$$;

-- enforce_slug runs as the writer, so the check stays callable by authenticated.
revoke execute on function better_supabase.slug_problem(text) from public, anon;
grant execute on function better_supabase.slug_problem(text) to authenticated, service_role;
revoke execute on function better_supabase.track_slug(regclass, text) from public, anon, authenticated;

-- blocks.reserved-slugs.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."slug_problem"(slug text)
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."slug_problem"($1) $$;
revoke execute on function "api"."slug_problem"(text) from public, anon;
grant execute on function "api"."slug_problem"(text) to authenticated, service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_06_reserved_slugs.sql
-- better-supabase module: reserved-slugs
-- @bsb-block-data reserved-slugs
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.reserved_slugs (slug, reason)
select value, 'system'
from unnest(array[
  'about', 'account', 'admin', 'api', 'app', 'assets', 'auth', 'billing', 'blog',
  'callback', 'cdn', 'dashboard', 'docs', 'help', 'invite', 'login', 'logout',
  'mail', 'new', 'oauth', 'onboarding', 'pricing', 'privacy', 'root', 'settings',
  'signin', 'signout', 'signup', 'static', 'status', 'support', 'system', 'terms',
  'www'
]) as value
on conflict (slug) do nothing;

insert into better_supabase.blocks (name, version, mode)
values ('reserved-slugs', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
