-- ==== alone: schema supabase/schemas/900_better_supabase_006_reserved_slugs.sql
-- better-supabase module: reserved-slugs
-- @bsb-block reserved-slugs@1 managed
-- @bsb-hash sha256:eb53087b0db758e41032343bcf0590469c9bea4938ac2ce90b483db4ee624dc0
-- A slug format and length check and a list of reserved words (admin, api, www, ...), enforced by a trigger.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create table "better_supabase"."reserved_slugs" (
  "slug" text primary key,
  "reason" text
);
alter table "better_supabase"."reserved_slugs" enable row level security;
-- enforce_slug runs as the writer, service_role included, and reads this list.
grant select on "better_supabase"."reserved_slugs" to anon, authenticated, service_role;
create policy bsb_reserved_slugs_read on "better_supabase"."reserved_slugs"
  for select to anon, authenticated, service_role
  using (true);

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
    when exists (select 1 from "better_supabase"."reserved_slugs" r where r."slug" = slug_problem.slug) then 'reserved'
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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_006_reserved_slugs.sql
-- better-supabase module: reserved-slugs
-- @bsb-block-data reserved-slugs
-- @bsb-hash sha256:af2300f3af4c9d5b1d275af2896940295208fbcc337e88e73115d74efc7f53e1
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into "better_supabase"."reserved_slugs" ("slug", "reason")
select value, 'system'
from unnest(array[
  'about', 'account', 'admin', 'api', 'app', 'assets', 'auth', 'billing', 'blog',
  'callback', 'cdn', 'dashboard', 'docs', 'help', 'invite', 'login', 'logout',
  'mail', 'new', 'oauth', 'onboarding', 'pricing', 'privacy', 'root', 'settings',
  'signin', 'signout', 'signup', 'static', 'status', 'support', 'system', 'terms',
  'www'
]) as value
on conflict ("slug") do nothing;

insert into better_supabase.blocks (name, version, mode)
values ('reserved-slugs', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_006_reserved_slugs.sql
-- better-supabase module: reserved-slugs
-- @bsb-block reserved-slugs@1 managed
-- @bsb-hash sha256:eb53087b0db758e41032343bcf0590469c9bea4938ac2ce90b483db4ee624dc0
-- A slug format and length check and a list of reserved words (admin, api, www, ...), enforced by a trigger.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create table "better_supabase"."reserved_slugs" (
  "slug" text primary key,
  "reason" text
);
alter table "better_supabase"."reserved_slugs" enable row level security;
-- enforce_slug runs as the writer, service_role included, and reads this list.
grant select on "better_supabase"."reserved_slugs" to anon, authenticated, service_role;
create policy bsb_reserved_slugs_read on "better_supabase"."reserved_slugs"
  for select to anon, authenticated, service_role
  using (true);

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
    when exists (select 1 from "better_supabase"."reserved_slugs" r where r."slug" = slug_problem.slug) then 'reserved'
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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_006_reserved_slugs.sql
-- better-supabase module: reserved-slugs
-- @bsb-block-data reserved-slugs
-- @bsb-hash sha256:af2300f3af4c9d5b1d275af2896940295208fbcc337e88e73115d74efc7f53e1
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into "better_supabase"."reserved_slugs" ("slug", "reason")
select value, 'system'
from unnest(array[
  'about', 'account', 'admin', 'api', 'app', 'assets', 'auth', 'billing', 'blog',
  'callback', 'cdn', 'dashboard', 'docs', 'help', 'invite', 'login', 'logout',
  'mail', 'new', 'oauth', 'onboarding', 'pricing', 'privacy', 'root', 'settings',
  'signin', 'signout', 'signup', 'static', 'status', 'support', 'system', 'terms',
  'www'
]) as value
on conflict ("slug") do nothing;

insert into better_supabase.blocks (name, version, mode)
values ('reserved-slugs', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_006_reserved_slugs.sql
-- better-supabase module: reserved-slugs
-- @bsb-block reserved-slugs@1 managed
-- @bsb-hash sha256:09983b5941d1ea01069a8cc575daa791594e8b7418f87617ae3cfe81b2c3bb17
-- A slug format and length check and a list of reserved words (admin, api, www, ...), enforced by a trigger.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;

create table "app_private"."reserved_slugs" (
  "slug" text primary key,
  "reason" text
);
alter table "app_private"."reserved_slugs" enable row level security;
-- enforce_slug runs as the writer, service_role included, and reads this list.
grant select on "app_private"."reserved_slugs" to anon, authenticated, service_role;
create policy bsb_reserved_slugs_read on "app_private"."reserved_slugs"
  for select to anon, authenticated, service_role
  using (true);

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
    when exists (select 1 from "app_private"."reserved_slugs" r where r."slug" = slug_problem.slug) then 'reserved'
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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_006_reserved_slugs.sql
-- better-supabase module: reserved-slugs
-- @bsb-block-data reserved-slugs
-- @bsb-hash sha256:787bb2f4c6eee8e73637b3fa6318277152421d9fb0f07b5f2d8eebd00fe2daf1
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into "app_private"."reserved_slugs" ("slug", "reason")
select value, 'system'
from unnest(array[
  'about', 'account', 'admin', 'api', 'app', 'assets', 'auth', 'billing', 'blog',
  'callback', 'cdn', 'dashboard', 'docs', 'help', 'invite', 'login', 'logout',
  'mail', 'new', 'oauth', 'onboarding', 'pricing', 'privacy', 'root', 'settings',
  'signin', 'signout', 'signup', 'static', 'status', 'support', 'system', 'terms',
  'www'
]) as value
on conflict ("slug") do nothing;

insert into better_supabase.blocks (name, version, mode)
values ('reserved-slugs', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_006_reserved_slugs.sql
-- better-supabase module: reserved-slugs
-- @bsb-block reserved-slugs@1 managed
-- @bsb-hash sha256:8efcb09b1f1dc9316613c941ec86edff65e57035f67a3f839483a60ae4c71e64
-- A slug format and length check and a list of reserved words (admin, api, www, ...), enforced by a trigger.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create table "better_supabase"."reserved_slugs" (
  "slug" text primary key,
  "reason" text
);
alter table "better_supabase"."reserved_slugs" enable row level security;
-- enforce_slug runs as the writer, service_role included, and reads this list.
grant select on "better_supabase"."reserved_slugs" to anon, authenticated, service_role;
create policy bsb_reserved_slugs_read on "better_supabase"."reserved_slugs"
  for select to anon, authenticated, service_role
  using (true);

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
    when exists (select 1 from "better_supabase"."reserved_slugs" r where r."slug" = slug_problem.slug) then 'reserved'
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
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."slug_problem"($1) $$;
revoke execute on function "api"."slug_problem"(text) from public, anon;
grant execute on function "api"."slug_problem"(text) to authenticated, service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_006_reserved_slugs.sql
-- better-supabase module: reserved-slugs
-- @bsb-block-data reserved-slugs
-- @bsb-hash sha256:af2300f3af4c9d5b1d275af2896940295208fbcc337e88e73115d74efc7f53e1
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into "better_supabase"."reserved_slugs" ("slug", "reason")
select value, 'system'
from unnest(array[
  'about', 'account', 'admin', 'api', 'app', 'assets', 'auth', 'billing', 'blog',
  'callback', 'cdn', 'dashboard', 'docs', 'help', 'invite', 'login', 'logout',
  'mail', 'new', 'oauth', 'onboarding', 'pricing', 'privacy', 'root', 'settings',
  'signin', 'signout', 'signup', 'static', 'status', 'support', 'system', 'terms',
  'www'
]) as value
on conflict ("slug") do nothing;

insert into better_supabase.blocks (name, version, mode)
values ('reserved-slugs', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_006_reserved_slugs.sql
-- better-supabase module: reserved-slugs
-- @bsb-block reserved-slugs@1 managed
-- @bsb-hash sha256:8fb39e47f813d46e5b70421cf0a6e88f3f83e997c054ab83b4bf253937d5445c
-- A slug format and length check and a list of reserved words (admin, api, www, ...), enforced by a trigger.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- better_supabase.reserved_slugs is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."reserved_slugs" add column if not exists "slug" text;
alter table "better_supabase"."reserved_slugs" add column if not exists "reason" text;
create unique index if not exists "bsb_reserved_slugs_slug_key" on "better_supabase"."reserved_slugs" ("slug");
alter table "better_supabase"."reserved_slugs" enable row level security;
-- enforce_slug runs as the writer, service_role included, and reads this list.
grant select on "better_supabase"."reserved_slugs" to anon, authenticated, service_role;
create policy bsb_reserved_slugs_read on "better_supabase"."reserved_slugs"
  for select to anon, authenticated, service_role
  using (true);

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
    when exists (select 1 from "better_supabase"."reserved_slugs" r where r."slug" = slug_problem.slug) then 'reserved'
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

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_006_reserved_slugs.sql
-- better-supabase module: reserved-slugs
-- @bsb-block-data reserved-slugs
-- @bsb-hash sha256:af2300f3af4c9d5b1d275af2896940295208fbcc337e88e73115d74efc7f53e1
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into "better_supabase"."reserved_slugs" ("slug", "reason")
select value, 'system'
from unnest(array[
  'about', 'account', 'admin', 'api', 'app', 'assets', 'auth', 'billing', 'blog',
  'callback', 'cdn', 'dashboard', 'docs', 'help', 'invite', 'login', 'logout',
  'mail', 'new', 'oauth', 'onboarding', 'pricing', 'privacy', 'root', 'settings',
  'signin', 'signout', 'signup', 'static', 'status', 'support', 'system', 'terms',
  'www'
]) as value
on conflict ("slug") do nothing;

insert into better_supabase.blocks (name, version, mode)
values ('reserved-slugs', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
