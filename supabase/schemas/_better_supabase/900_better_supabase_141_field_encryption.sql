-- better-supabase module: field-encryption
-- @bsb-block field-encryption@1 managed
-- Encrypts app table columns and custom field values at rest with a data key per tenant, user or app, kept in Supabase Vault as bs:field-key:<owner>. Only security definer read paths that check the caller's scope decrypt; drop_field_key deletes a key so its values can no longer be read.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create extension if not exists pgcrypto with schema extensions;

-- Field data keys live only in Vault, one per owner (tenant:<id>, user:<id>
-- or app), as bs:field-key:<owner>. No API role calls field_key, field_seal
-- or field_open; security definer functions of app tables and custom fields
-- do, after they check the caller's scope.
create or replace function "better_supabase"."field_key"(owner text, make boolean default true)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_key text;
begin
  if field_key.owner is null or length(field_key.owner) = 0 then
    raise exception 'a field key needs an owner' using errcode = '22023', hint = 'FIELD_KEY_OWNER';
  end if;
  select ds.decrypted_secret into v_key from vault.decrypted_secrets ds
  where ds.name = 'bs:field-key:' || field_key.owner;
  if v_key is not null or not field_key.make then
    return v_key;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('bs:field-key:' || field_key.owner, 0));
  select ds.decrypted_secret into v_key from vault.decrypted_secrets ds
  where ds.name = 'bs:field-key:' || field_key.owner;
  if v_key is null then
    v_key := encode(extensions.gen_random_bytes(32), 'base64');
    perform vault.create_secret(v_key, 'bs:field-key:' || field_key.owner, 'better-supabase field encryption key');
  end if;
  return v_key;
end;
$$;
revoke execute on function "better_supabase"."field_key"(text, boolean) from public, anon, authenticated, service_role;

-- Encrypts a value with a data key: bsf1: then base64 of an OpenPGP message.
create or replace function "better_supabase"."field_seal"(key text, value text)
returns text
language sql
volatile
set search_path = ''
as $$
  select case when field_seal.value is null then null
    else 'bsf1:' || translate(encode(extensions.pgp_sym_encrypt(field_seal.value, field_seal.key, 'cipher-algo=aes256, s2k-mode=1'), 'base64'), E'\n', '')
  end
$$;
revoke execute on function "better_supabase"."field_seal"(text, text) from public, anon, authenticated, service_role;

-- Decrypts a value; a value without the prefix was stored before the column
-- was encrypted and comes back as it is. null when the key is gone.
create or replace function "better_supabase"."field_open"(key text, value text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when field_open.value is null then null
    when left(field_open.value, 5) <> 'bsf1:' then field_open.value
    when field_open.key is null then null
    else extensions.pgp_sym_decrypt(decode(substr(field_open.value, 6), 'base64'), field_open.key)
  end
$$;
revoke execute on function "better_supabase"."field_open"(text, text) from public, anon, authenticated, service_role;

-- Encrypts a value with the owner's key, creating the key on first use.
create or replace function "better_supabase"."field_encrypt"(owner text, value text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
begin
  if field_encrypt.value is null then
    return null;
  end if;
  return "better_supabase"."field_seal"("better_supabase"."field_key"(field_encrypt.owner, true), field_encrypt.value);
end;
$$;
revoke execute on function "better_supabase"."field_encrypt"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."field_encrypt"(text, text) to service_role;

-- Decrypts a value with the owner's key; null when the key was dropped.
create or replace function "better_supabase"."field_decrypt"(owner text, value text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
begin
  if field_decrypt.value is null then
    return null;
  end if;
  return "better_supabase"."field_open"("better_supabase"."field_key"(field_decrypt.owner, false), field_decrypt.value);
end;
$$;
revoke execute on function "better_supabase"."field_decrypt"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."field_decrypt"(text, text) to service_role;

-- Deletes an owner's key, so every value encrypted with it reads as null
-- (crypto-shredding, for example after a tenant is erased).
create or replace function "better_supabase"."drop_field_key"(owner text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role drops field keys' using errcode = '42501', hint = 'FIELD_KEY_FORBIDDEN';
  end if;
  delete from vault.secrets s where s.name = 'bs:field-key:' || drop_field_key.owner;
  if not found then
    return false;
  end if;
  perform "better_supabase".emit_event('field_key.dropped', jsonb_build_object('owner', drop_field_key.owner), 'field-keys/' || drop_field_key.owner, null, null, 'better-supabase/field-encryption');
  perform better_supabase.audit_event(
    event_type => 'field_key.dropped',
    category => 'security',
    target_type => 'field_key',
    record_id => drop_field_key.owner,
    metadata => jsonb_build_object('owner', drop_field_key.owner)
  );
  return true;
end;
$$;
revoke execute on function "better_supabase"."drop_field_key"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."drop_field_key"(text) to service_role;

-- blocks.field-encryption.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."field_encrypt"(owner text, value text)
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."field_encrypt"($1, $2) $$;
revoke execute on function "api"."field_encrypt"(text, text) from public, anon, authenticated;
grant execute on function "api"."field_encrypt"(text, text) to service_role;

create or replace function "api"."field_decrypt"(owner text, value text)
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."field_decrypt"($1, $2) $$;
revoke execute on function "api"."field_decrypt"(text, text) from public, anon, authenticated;
grant execute on function "api"."field_decrypt"(text, text) to service_role;

create or replace function "api"."drop_field_key"(owner text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drop_field_key"($1) $$;
revoke execute on function "api"."drop_field_key"(text) from public, anon, authenticated;
grant execute on function "api"."drop_field_key"(text) to service_role;

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
