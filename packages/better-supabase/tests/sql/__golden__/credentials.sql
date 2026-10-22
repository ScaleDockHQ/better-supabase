-- ==== alone: schema supabase/schemas/900_better_supabase_41_credentials.sql
-- better-supabase module: credentials
-- @bsb-block credentials@1 managed
-- Third-party tokens and API keys in Supabase Vault as bs:cred:<provider>:<name>, behind security definer credential_get, credential_set and credential_delete functions only the service role may call. vaultCredentials() in better-supabase/credentials resolves credential references through them.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Third-party credentials live in Vault as bs:cred:<provider>:<name>; tables
-- keep a credential_ref that names them, never the secret. Only the service
-- role reads or writes them.
create or replace function "better_supabase"."credential_get"(provider text, name text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role reads and writes credentials'
      using errcode = '42501', hint = 'CREDENTIALS_FORBIDDEN';
  end if;
  if credential_get.provider !~ '^[a-z][a-z0-9-]{0,39}$' or credential_get.name !~ '^[A-Za-z0-9][A-Za-z0-9:._/@-]{0,199}$' then
    raise exception 'credential names are a provider and a name of letters, digits and :._/@-'
      using errcode = 'P0001', hint = 'CREDENTIAL_NAME_INVALID';
  end if;
  return (
    select ds.decrypted_secret from vault.decrypted_secrets ds
    where ds.name = 'bs:cred:' || credential_get.provider || ':' || credential_get.name
  );
end;
$$;
revoke execute on function "better_supabase"."credential_get"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."credential_get"(text, text) to service_role;

-- Stores or replaces a credential; returns its Vault id.
create or replace function "better_supabase"."credential_set"(provider text, name text, secret text, description text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role reads and writes credentials'
      using errcode = '42501', hint = 'CREDENTIALS_FORBIDDEN';
  end if;
  if credential_set.provider !~ '^[a-z][a-z0-9-]{0,39}$' or credential_set.name !~ '^[A-Za-z0-9][A-Za-z0-9:._/@-]{0,199}$' then
    raise exception 'credential names are a provider and a name of letters, digits and :._/@-'
      using errcode = 'P0001', hint = 'CREDENTIAL_NAME_INVALID';
  end if;
  if credential_set.secret is null or length(credential_set.secret) = 0 then
    raise exception 'a credential needs a value'
      using errcode = 'P0001', hint = 'CREDENTIAL_EMPTY';
  end if;
  select s.id into v_id from vault.secrets s where s.name = 'bs:cred:' || credential_set.provider || ':' || credential_set.name;
  if v_id is null then
    v_id := vault.create_secret(
      credential_set.secret,
      'bs:cred:' || credential_set.provider || ':' || credential_set.name,
      coalesce(credential_set.description, 'better-supabase credential')
    );
  else
    perform vault.update_secret(v_id, credential_set.secret);
  end if;
  null;
  return v_id;
end;
$$;
revoke execute on function "better_supabase"."credential_set"(text, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."credential_set"(text, text, text, text) to service_role;

-- Deletes a credential; false when there was none.
create or replace function "better_supabase"."credential_delete"(provider text, name text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role reads and writes credentials'
      using errcode = '42501', hint = 'CREDENTIALS_FORBIDDEN';
  end if;
  if credential_delete.provider !~ '^[a-z][a-z0-9-]{0,39}$' or credential_delete.name !~ '^[A-Za-z0-9][A-Za-z0-9:._/@-]{0,199}$' then
    raise exception 'credential names are a provider and a name of letters, digits and :._/@-'
      using errcode = 'P0001', hint = 'CREDENTIAL_NAME_INVALID';
  end if;
  delete from vault.secrets s where s.name = 'bs:cred:' || credential_delete.provider || ':' || credential_delete.name;
  if not found then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."credential_delete"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."credential_delete"(text, text) to service_role;

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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_41_credentials.sql
-- better-supabase module: credentials
-- @bsb-block-data credentials
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('credentials', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_41_credentials.sql
-- better-supabase module: credentials
-- @bsb-block credentials@1 managed
-- Third-party tokens and API keys in Supabase Vault as bs:cred:<provider>:<name>, behind security definer credential_get, credential_set and credential_delete functions only the service role may call. vaultCredentials() in better-supabase/credentials resolves credential references through them.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Third-party credentials live in Vault as bs:cred:<provider>:<name>; tables
-- keep a credential_ref that names them, never the secret. Only the service
-- role reads or writes them.
create or replace function "better_supabase"."credential_get"(provider text, name text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role reads and writes credentials'
      using errcode = '42501', hint = 'CREDENTIALS_FORBIDDEN';
  end if;
  if credential_get.provider !~ '^[a-z][a-z0-9-]{0,39}$' or credential_get.name !~ '^[A-Za-z0-9][A-Za-z0-9:._/@-]{0,199}$' then
    raise exception 'credential names are a provider and a name of letters, digits and :._/@-'
      using errcode = 'P0001', hint = 'CREDENTIAL_NAME_INVALID';
  end if;
  return (
    select ds.decrypted_secret from vault.decrypted_secrets ds
    where ds.name = 'bs:cred:' || credential_get.provider || ':' || credential_get.name
  );
end;
$$;
revoke execute on function "better_supabase"."credential_get"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."credential_get"(text, text) to service_role;

-- Stores or replaces a credential; returns its Vault id.
create or replace function "better_supabase"."credential_set"(provider text, name text, secret text, description text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role reads and writes credentials'
      using errcode = '42501', hint = 'CREDENTIALS_FORBIDDEN';
  end if;
  if credential_set.provider !~ '^[a-z][a-z0-9-]{0,39}$' or credential_set.name !~ '^[A-Za-z0-9][A-Za-z0-9:._/@-]{0,199}$' then
    raise exception 'credential names are a provider and a name of letters, digits and :._/@-'
      using errcode = 'P0001', hint = 'CREDENTIAL_NAME_INVALID';
  end if;
  if credential_set.secret is null or length(credential_set.secret) = 0 then
    raise exception 'a credential needs a value'
      using errcode = 'P0001', hint = 'CREDENTIAL_EMPTY';
  end if;
  select s.id into v_id from vault.secrets s where s.name = 'bs:cred:' || credential_set.provider || ':' || credential_set.name;
  if v_id is null then
    v_id := vault.create_secret(
      credential_set.secret,
      'bs:cred:' || credential_set.provider || ':' || credential_set.name,
      coalesce(credential_set.description, 'better-supabase credential')
    );
  else
    perform vault.update_secret(v_id, credential_set.secret);
  end if;
  perform "better_supabase".emit_event('credential.set', jsonb_build_object('provider', credential_set.provider, 'name', credential_set.name), 'credentials/' || credential_set.provider || '/' || credential_set.name, null, null, 'better-supabase/credentials');
  perform better_supabase.audit_event(
    event_type => 'credential.set',
    category => 'security',
    target_type => 'credential',
    record_id => credential_set.provider || ':' || credential_set.name,
    metadata => jsonb_build_object('provider', credential_set.provider, 'name', credential_set.name)
  );
  return v_id;
end;
$$;
revoke execute on function "better_supabase"."credential_set"(text, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."credential_set"(text, text, text, text) to service_role;

-- Deletes a credential; false when there was none.
create or replace function "better_supabase"."credential_delete"(provider text, name text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role reads and writes credentials'
      using errcode = '42501', hint = 'CREDENTIALS_FORBIDDEN';
  end if;
  if credential_delete.provider !~ '^[a-z][a-z0-9-]{0,39}$' or credential_delete.name !~ '^[A-Za-z0-9][A-Za-z0-9:._/@-]{0,199}$' then
    raise exception 'credential names are a provider and a name of letters, digits and :._/@-'
      using errcode = 'P0001', hint = 'CREDENTIAL_NAME_INVALID';
  end if;
  delete from vault.secrets s where s.name = 'bs:cred:' || credential_delete.provider || ':' || credential_delete.name;
  if not found then
    return false;
  end if;
  perform "better_supabase".emit_event('credential.deleted', jsonb_build_object('provider', credential_delete.provider, 'name', credential_delete.name), 'credentials/' || credential_delete.provider || '/' || credential_delete.name, null, null, 'better-supabase/credentials');
  perform better_supabase.audit_event(
    event_type => 'credential.deleted',
    category => 'security',
    target_type => 'credential',
    record_id => credential_delete.provider || ':' || credential_delete.name,
    metadata => jsonb_build_object('provider', credential_delete.provider, 'name', credential_delete.name)
  );
  return true;
end;
$$;
revoke execute on function "better_supabase"."credential_delete"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."credential_delete"(text, text) to service_role;

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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_41_credentials.sql
-- better-supabase module: credentials
-- @bsb-block-data credentials
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('credentials', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_41_credentials.sql
-- better-supabase module: credentials
-- @bsb-block credentials@1 managed
-- Third-party tokens and API keys in Supabase Vault as bs:cred:<provider>:<name>, behind security definer credential_get, credential_set and credential_delete functions only the service role may call. vaultCredentials() in better-supabase/credentials resolves credential references through them.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
-- Third-party credentials live in Vault as bs:cred:<provider>:<name>; tables
-- keep a credential_ref that names them, never the secret. Only the service
-- role reads or writes them.
create or replace function "app_private"."credential_get"(provider text, name text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role reads and writes credentials'
      using errcode = '42501', hint = 'CREDENTIALS_FORBIDDEN';
  end if;
  if credential_get.provider !~ '^[a-z][a-z0-9-]{0,39}$' or credential_get.name !~ '^[A-Za-z0-9][A-Za-z0-9:._/@-]{0,199}$' then
    raise exception 'credential names are a provider and a name of letters, digits and :._/@-'
      using errcode = 'P0001', hint = 'CREDENTIAL_NAME_INVALID';
  end if;
  return (
    select ds.decrypted_secret from vault.decrypted_secrets ds
    where ds.name = 'bs:cred:' || credential_get.provider || ':' || credential_get.name
  );
end;
$$;
revoke execute on function "app_private"."credential_get"(text, text) from public, anon, authenticated;
grant execute on function "app_private"."credential_get"(text, text) to service_role;

-- Stores or replaces a credential; returns its Vault id.
create or replace function "app_private"."credential_set"(provider text, name text, secret text, description text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role reads and writes credentials'
      using errcode = '42501', hint = 'CREDENTIALS_FORBIDDEN';
  end if;
  if credential_set.provider !~ '^[a-z][a-z0-9-]{0,39}$' or credential_set.name !~ '^[A-Za-z0-9][A-Za-z0-9:._/@-]{0,199}$' then
    raise exception 'credential names are a provider and a name of letters, digits and :._/@-'
      using errcode = 'P0001', hint = 'CREDENTIAL_NAME_INVALID';
  end if;
  if credential_set.secret is null or length(credential_set.secret) = 0 then
    raise exception 'a credential needs a value'
      using errcode = 'P0001', hint = 'CREDENTIAL_EMPTY';
  end if;
  select s.id into v_id from vault.secrets s where s.name = 'bs:cred:' || credential_set.provider || ':' || credential_set.name;
  if v_id is null then
    v_id := vault.create_secret(
      credential_set.secret,
      'bs:cred:' || credential_set.provider || ':' || credential_set.name,
      coalesce(credential_set.description, 'better-supabase credential')
    );
  else
    perform vault.update_secret(v_id, credential_set.secret);
  end if;
  null;
  return v_id;
end;
$$;
revoke execute on function "app_private"."credential_set"(text, text, text, text) from public, anon, authenticated;
grant execute on function "app_private"."credential_set"(text, text, text, text) to service_role;

-- Deletes a credential; false when there was none.
create or replace function "app_private"."credential_delete"(provider text, name text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role reads and writes credentials'
      using errcode = '42501', hint = 'CREDENTIALS_FORBIDDEN';
  end if;
  if credential_delete.provider !~ '^[a-z][a-z0-9-]{0,39}$' or credential_delete.name !~ '^[A-Za-z0-9][A-Za-z0-9:._/@-]{0,199}$' then
    raise exception 'credential names are a provider and a name of letters, digits and :._/@-'
      using errcode = 'P0001', hint = 'CREDENTIAL_NAME_INVALID';
  end if;
  delete from vault.secrets s where s.name = 'bs:cred:' || credential_delete.provider || ':' || credential_delete.name;
  if not found then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."credential_delete"(text, text) from public, anon, authenticated;
grant execute on function "app_private"."credential_delete"(text, text) to service_role;

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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_41_credentials.sql
-- better-supabase module: credentials
-- @bsb-block-data credentials
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('credentials', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_41_credentials.sql
-- better-supabase module: credentials
-- @bsb-block credentials@1 managed
-- Third-party tokens and API keys in Supabase Vault as bs:cred:<provider>:<name>, behind security definer credential_get, credential_set and credential_delete functions only the service role may call. vaultCredentials() in better-supabase/credentials resolves credential references through them.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Third-party credentials live in Vault as bs:cred:<provider>:<name>; tables
-- keep a credential_ref that names them, never the secret. Only the service
-- role reads or writes them.
create or replace function "better_supabase"."credential_get"(provider text, name text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role reads and writes credentials'
      using errcode = '42501', hint = 'CREDENTIALS_FORBIDDEN';
  end if;
  if credential_get.provider !~ '^[a-z][a-z0-9-]{0,39}$' or credential_get.name !~ '^[A-Za-z0-9][A-Za-z0-9:._/@-]{0,199}$' then
    raise exception 'credential names are a provider and a name of letters, digits and :._/@-'
      using errcode = 'P0001', hint = 'CREDENTIAL_NAME_INVALID';
  end if;
  return (
    select ds.decrypted_secret from vault.decrypted_secrets ds
    where ds.name = 'bs:cred:' || credential_get.provider || ':' || credential_get.name
  );
end;
$$;
revoke execute on function "better_supabase"."credential_get"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."credential_get"(text, text) to service_role;

-- Stores or replaces a credential; returns its Vault id.
create or replace function "better_supabase"."credential_set"(provider text, name text, secret text, description text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role reads and writes credentials'
      using errcode = '42501', hint = 'CREDENTIALS_FORBIDDEN';
  end if;
  if credential_set.provider !~ '^[a-z][a-z0-9-]{0,39}$' or credential_set.name !~ '^[A-Za-z0-9][A-Za-z0-9:._/@-]{0,199}$' then
    raise exception 'credential names are a provider and a name of letters, digits and :._/@-'
      using errcode = 'P0001', hint = 'CREDENTIAL_NAME_INVALID';
  end if;
  if credential_set.secret is null or length(credential_set.secret) = 0 then
    raise exception 'a credential needs a value'
      using errcode = 'P0001', hint = 'CREDENTIAL_EMPTY';
  end if;
  select s.id into v_id from vault.secrets s where s.name = 'bs:cred:' || credential_set.provider || ':' || credential_set.name;
  if v_id is null then
    v_id := vault.create_secret(
      credential_set.secret,
      'bs:cred:' || credential_set.provider || ':' || credential_set.name,
      coalesce(credential_set.description, 'better-supabase credential')
    );
  else
    perform vault.update_secret(v_id, credential_set.secret);
  end if;
  null;
  return v_id;
end;
$$;
revoke execute on function "better_supabase"."credential_set"(text, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."credential_set"(text, text, text, text) to service_role;

-- Deletes a credential; false when there was none.
create or replace function "better_supabase"."credential_delete"(provider text, name text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role reads and writes credentials'
      using errcode = '42501', hint = 'CREDENTIALS_FORBIDDEN';
  end if;
  if credential_delete.provider !~ '^[a-z][a-z0-9-]{0,39}$' or credential_delete.name !~ '^[A-Za-z0-9][A-Za-z0-9:._/@-]{0,199}$' then
    raise exception 'credential names are a provider and a name of letters, digits and :._/@-'
      using errcode = 'P0001', hint = 'CREDENTIAL_NAME_INVALID';
  end if;
  delete from vault.secrets s where s.name = 'bs:cred:' || credential_delete.provider || ':' || credential_delete.name;
  if not found then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."credential_delete"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."credential_delete"(text, text) to service_role;

-- blocks.credentials.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."credential_get"(provider text, name text)
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."credential_get"($1, $2) $$;
revoke execute on function "api"."credential_get"(text, text) from public, anon, authenticated;
grant execute on function "api"."credential_get"(text, text) to service_role;

create or replace function "api"."credential_set"(provider text, name text, secret text, description text default null)
returns uuid
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."credential_set"($1, $2, $3, $4) $$;
revoke execute on function "api"."credential_set"(text, text, text, text) from public, anon, authenticated;
grant execute on function "api"."credential_set"(text, text, text, text) to service_role;

create or replace function "api"."credential_delete"(provider text, name text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."credential_delete"($1, $2) $$;
revoke execute on function "api"."credential_delete"(text, text) from public, anon, authenticated;
grant execute on function "api"."credential_delete"(text, text) to service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_41_credentials.sql
-- better-supabase module: credentials
-- @bsb-block-data credentials
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('credentials', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== adopt: schema supabase/schemas/900_better_supabase_41_credentials.sql
-- better-supabase module: credentials
-- @bsb-block credentials@1 adopt
-- Third-party tokens and API keys in Supabase Vault as bs:cred:<provider>:<name>, behind security definer credential_get, credential_set and credential_delete functions only the service role may call. vaultCredentials() in better-supabase/credentials resolves credential references through them.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Third-party credentials live in the app's "better_supabase"."credentials", each row naming its Vault secret. Only the service role reads or writes them.
create or replace function "better_supabase"."credential_get"(provider text, name text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_provider text := credential_get.provider;
  v_name text := credential_get.name;
  v_tenant text;
  v_scope text;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role reads and writes credentials'
      using errcode = '42501', hint = 'CREDENTIALS_FORBIDDEN';
  end if;
  if credential_get.provider !~ '^[a-z][a-z0-9-]{0,39}$' or credential_get.name !~ '^[A-Za-z0-9][A-Za-z0-9:._/@-]{0,199}$' then
    raise exception 'credential names are a provider and a name of letters, digits and :._/@-'
      using errcode = 'P0001', hint = 'CREDENTIAL_NAME_INVALID';
  end if;
  if v_name ~ '^tenant/[^/]+/.' then
    v_tenant := split_part(v_name, '/', 2);
    v_name := substr(v_name, length(v_tenant) + 9);
  end if;
  if v_name ~ '@[^@/]+$' then
    v_scope := substring(v_name from '@([^@/]+)$');
    v_name := left(v_name, length(v_name) - length(v_scope) - 1);
  end if;
  if v_provider = 'vault' and position(':' in v_name) > 1 then
    v_provider := split_part(v_name, ':', 1);
    v_name := substr(v_name, length(v_provider) + 2);
  end if;
  return (
    select ds.decrypted_secret from "better_supabase"."credentials" s
    join vault.decrypted_secrets ds on ds.id = s."vault_id"
    where s."provider"::text = v_provider and s."name"::text = v_name and s."tenant"::text is not distinct from v_tenant and s."scope"::text is not distinct from v_scope
    limit 1
  );
end;
$$;
revoke execute on function "better_supabase"."credential_get"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."credential_get"(text, text) to service_role;

-- Stores or replaces a credential; returns its row's Vault id, or null when
-- the table keeps the secret in a column.
create or replace function "better_supabase"."credential_set"(provider text, name text, secret text, description text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_provider text := credential_set.provider;
  v_name text := credential_set.name;
  v_tenant text;
  v_scope text;
  v_found boolean;
  v_vault uuid;
  v_row "better_supabase"."credentials";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role reads and writes credentials'
      using errcode = '42501', hint = 'CREDENTIALS_FORBIDDEN';
  end if;
  if credential_set.provider !~ '^[a-z][a-z0-9-]{0,39}$' or credential_set.name !~ '^[A-Za-z0-9][A-Za-z0-9:._/@-]{0,199}$' then
    raise exception 'credential names are a provider and a name of letters, digits and :._/@-'
      using errcode = 'P0001', hint = 'CREDENTIAL_NAME_INVALID';
  end if;
  if credential_set.secret is null or length(credential_set.secret) = 0 then
    raise exception 'a credential needs a value'
      using errcode = 'P0001', hint = 'CREDENTIAL_EMPTY';
  end if;
  if v_name ~ '^tenant/[^/]+/.' then
    v_tenant := split_part(v_name, '/', 2);
    v_name := substr(v_name, length(v_tenant) + 9);
  end if;
  if v_name ~ '@[^@/]+$' then
    v_scope := substring(v_name from '@([^@/]+)$');
    v_name := left(v_name, length(v_name) - length(v_scope) - 1);
  end if;
  if v_provider = 'vault' and position(':' in v_name) > 1 then
    v_provider := split_part(v_name, ':', 1);
    v_name := substr(v_name, length(v_provider) + 2);
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'bs:cred:' || v_provider || ':' || v_name || ':' || coalesce(v_tenant, '') || ':' || coalesce(v_scope, ''), 0));
  select true, s."vault_id" into v_found, v_vault from "better_supabase"."credentials" s where s."provider"::text = v_provider and s."name"::text = v_name and s."tenant"::text is not distinct from v_tenant and s."scope"::text is not distinct from v_scope limit 1;
  if v_vault is null then
    v_vault := vault.create_secret(
      credential_set.secret,
      'bs:cred:' || v_provider || ':' || v_name || ':' || gen_random_uuid()::text,
      coalesce(credential_set.description, 'better-supabase credential')
    );
  else
    perform vault.update_secret(v_vault, credential_set.secret);
  end if;
  if v_found then
    update "better_supabase"."credentials" s set "vault_id" = v_vault, "updated_at" = now() where s."provider"::text = v_provider and s."name"::text = v_name and s."tenant"::text is not distinct from v_tenant and s."scope"::text is not distinct from v_scope;
  else
    v_row := jsonb_populate_record(null::"better_supabase"."credentials", jsonb_build_object(
      'provider', v_provider,
      'name', v_name,
      'tenant', v_tenant,
      'scope', v_scope
    ));
    insert into "better_supabase"."credentials" ("provider", "name", "tenant", "scope", "vault_id", "updated_at")
    values (v_row."provider", v_row."name", v_row."tenant", v_row."scope", v_vault, now());
  end if;
  null;
  return v_vault;
end;
$$;
revoke execute on function "better_supabase"."credential_set"(text, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."credential_set"(text, text, text, text) to service_role;

-- Deletes a credential; false when there was none.
create or replace function "better_supabase"."credential_delete"(provider text, name text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_provider text := credential_delete.provider;
  v_name text := credential_delete.name;
  v_tenant text;
  v_scope text;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role reads and writes credentials'
      using errcode = '42501', hint = 'CREDENTIALS_FORBIDDEN';
  end if;
  if credential_delete.provider !~ '^[a-z][a-z0-9-]{0,39}$' or credential_delete.name !~ '^[A-Za-z0-9][A-Za-z0-9:._/@-]{0,199}$' then
    raise exception 'credential names are a provider and a name of letters, digits and :._/@-'
      using errcode = 'P0001', hint = 'CREDENTIAL_NAME_INVALID';
  end if;
  if v_name ~ '^tenant/[^/]+/.' then
    v_tenant := split_part(v_name, '/', 2);
    v_name := substr(v_name, length(v_tenant) + 9);
  end if;
  if v_name ~ '@[^@/]+$' then
    v_scope := substring(v_name from '@([^@/]+)$');
    v_name := left(v_name, length(v_name) - length(v_scope) - 1);
  end if;
  if v_provider = 'vault' and position(':' in v_name) > 1 then
    v_provider := split_part(v_name, ':', 1);
    v_name := substr(v_name, length(v_provider) + 2);
  end if;
  delete from "better_supabase"."credentials" s where s."provider"::text = v_provider and s."name"::text = v_name and s."tenant"::text is not distinct from v_tenant and s."scope"::text is not distinct from v_scope;
  if not found then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."credential_delete"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."credential_delete"(text, text) to service_role;

create or replace function "better_supabase"."drop_credential_vault_secret"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' or old."vault_id" is distinct from new."vault_id" then
    delete from vault.secrets vs where vs.id = old."vault_id";
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."drop_credential_vault_secret"() from public, anon, authenticated;
drop trigger if exists "bsb_credential_vault" on "better_supabase"."credentials";
create trigger "bsb_credential_vault" after delete or update of "vault_id" on "better_supabase"."credentials"
  for each row execute function "better_supabase"."drop_credential_vault_secret"();

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

-- ==== adopt: data supabase/better-supabase-data/900_better_supabase_41_credentials.sql
-- better-supabase module: credentials
-- @bsb-block-data credentials
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('credentials', 1, 'adopt')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
