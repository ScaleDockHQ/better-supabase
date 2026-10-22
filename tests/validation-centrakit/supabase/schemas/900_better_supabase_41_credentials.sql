-- better-supabase module: credentials
-- @bsb-block credentials@1 adopt
-- Third-party tokens and API keys in Supabase Vault as bs:cred:<provider>:<name>, behind security definer credential_get, credential_set and credential_delete functions only the service role may call. vaultCredentials() in better-supabase/credentials resolves credential references through them.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Third-party credentials live in the app's "centrakit"."integration_credentials", each row naming its Vault secret. Only the service role reads or writes them.
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
  if v_provider = 'vault' and position(':' in v_name) > 1 then
    v_provider := split_part(v_name, ':', 1);
    v_name := substr(v_name, length(v_provider) + 2);
  end if;
  return (
    select ds.decrypted_secret from "centrakit"."integration_credentials" s
    join vault.decrypted_secrets ds on ds.id = s."vault_secret_id"
    where s."provider"::text = v_provider and s."key"::text = v_name and s."organization_id"::text is not distinct from v_tenant
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
  v_row "centrakit"."integration_credentials";
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
  if v_provider = 'vault' and position(':' in v_name) > 1 then
    v_provider := split_part(v_name, ':', 1);
    v_name := substr(v_name, length(v_provider) + 2);
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'bs:cred:' || v_provider || ':' || v_name || ':' || coalesce(v_tenant, '') || ':' || coalesce(v_scope, ''), 0));
  select true, s."vault_secret_id" into v_found, v_vault from "centrakit"."integration_credentials" s where s."provider"::text = v_provider and s."key"::text = v_name and s."organization_id"::text is not distinct from v_tenant limit 1;
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
    update "centrakit"."integration_credentials" s set "vault_secret_id" = v_vault, "updated_at" = now() where s."provider"::text = v_provider and s."key"::text = v_name and s."organization_id"::text is not distinct from v_tenant;
  else
    v_row := jsonb_populate_record(null::"centrakit"."integration_credentials", jsonb_build_object(
      'provider', v_provider,
      'key', v_name,
      'organization_id', v_tenant
    ));
    insert into "centrakit"."integration_credentials" ("provider", "key", "organization_id", "vault_secret_id", "updated_at")
    values (v_row."provider", v_row."key", v_row."organization_id", v_vault, now());
  end if;
  perform "better_supabase".emit_event('credential.set', jsonb_build_object('provider', credential_set.provider, 'name', credential_set.name), 'credentials/' || credential_set.provider || '/' || credential_set.name, null, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'credential.set',
    category => 'security',
    target_type => 'credential',
    record_id => credential_set.provider || ':' || credential_set.name,
    metadata => jsonb_build_object('provider', credential_set.provider, 'name', credential_set.name)
  );
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
  if v_provider = 'vault' and position(':' in v_name) > 1 then
    v_provider := split_part(v_name, ':', 1);
    v_name := substr(v_name, length(v_provider) + 2);
  end if;
  delete from "centrakit"."integration_credentials" s where s."provider"::text = v_provider and s."key"::text = v_name and s."organization_id"::text is not distinct from v_tenant;
  if not found then
    return false;
  end if;
  perform "better_supabase".emit_event('credential.deleted', jsonb_build_object('provider', credential_delete.provider, 'name', credential_delete.name), 'credentials/' || credential_delete.provider || '/' || credential_delete.name, null, null, 'domain');
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

create or replace function "better_supabase"."drop_credential_vault_secret"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' or old."vault_secret_id" is distinct from new."vault_secret_id" then
    delete from vault.secrets vs where vs.id = old."vault_secret_id";
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."drop_credential_vault_secret"() from public, anon, authenticated;
drop trigger if exists "bsb_credential_vault" on "centrakit"."integration_credentials";
create trigger "bsb_credential_vault" after delete or update of "vault_secret_id" on "centrakit"."integration_credentials"
  for each row execute function "better_supabase"."drop_credential_vault_secret"();

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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;
