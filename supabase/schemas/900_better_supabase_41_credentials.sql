-- better-supabase module: credentials (0.5.1)
-- @bs-module credentials@1 managed
-- Third-party tokens and API keys in Supabase Vault as bs:cred:<provider>:<name>, behind security definer credential_get, credential_set and credential_delete functions only the service role may call. vaultCredentials() in better-supabase/credentials resolves credential references through them.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

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

-- sql.modules.credentials.api: entry points for the Data API.
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
