-- ==== alone: schema supabase/schemas/900_better_supabase_141_field_encryption.sql
-- better-supabase module: field-encryption
-- @bsb-block field-encryption@2 managed
-- @bsb-hash sha256:6044f154650ca0fa7057a6c9306fecf7148e70945f12c15cd59c7945090f95e8
-- Encrypts app table columns and custom field values at rest with a data key per tenant, user or app, kept in Supabase Vault as bs:field-key:<owner>. Only security definer read paths that check the caller's scope decrypt; a lookup column keeps an HMAC of the value under the owner's lookup key for equality searches; drop_field_key deletes both keys so the values can no longer be read or found. Members read which of their owners have keys, with the key dates and what they encrypt, through field_key_status(), and rotate_field_key replaces a data key and encrypts its values again.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists pgcrypto with schema extensions;

-- Field data keys live only in Vault, one per owner (tenant:<id>, user:<id>
-- or app), as bs:field-key:<owner>, and the lookup keys next to them as
-- bs:field-lookup-key:<owner>. No API role calls field_key, field_lookup_key,
-- field_seal, field_open or field_hash; security definer functions of app
-- tables and custom fields do, after they check the caller's scope.
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

create or replace function "better_supabase"."field_lookup_key"(owner text, make boolean default true)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_key text;
begin
  if field_lookup_key.owner is null or length(field_lookup_key.owner) = 0 then
    raise exception 'a field key needs an owner' using errcode = '22023', hint = 'FIELD_KEY_OWNER';
  end if;
  select ds.decrypted_secret into v_key from vault.decrypted_secrets ds
  where ds.name = 'bs:field-lookup-key:' || field_lookup_key.owner;
  if v_key is not null or not field_lookup_key.make then
    return v_key;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('bs:field-lookup-key:' || field_lookup_key.owner, 0));
  select ds.decrypted_secret into v_key from vault.decrypted_secrets ds
  where ds.name = 'bs:field-lookup-key:' || field_lookup_key.owner;
  if v_key is null then
    v_key := encode(extensions.gen_random_bytes(32), 'base64');
    perform vault.create_secret(v_key, 'bs:field-lookup-key:' || field_lookup_key.owner, 'better-supabase field lookup key');
  end if;
  return v_key;
end;
$$;
revoke execute on function "better_supabase"."field_lookup_key"(text, boolean) from public, anon, authenticated, service_role;

-- Encrypts a value with a data key: bsf1: then base64 of an OpenPGP message.
create or replace function "better_supabase"."field_seal"(key text, value text)
returns text
language sql
volatile
set search_path = ''
as $$
  select case when field_seal.value is null then null
    when left(field_seal.value, 5) = 'bsf1:' then field_seal.value
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

-- The lookup hash of a value: HMAC-SHA256 of the value, lowercased and
-- without whitespace, under a lookup key. null without a key or a value.
create or replace function "better_supabase"."field_hash"(key text, value text)
returns bytea
language sql
immutable
set search_path = ''
as $$
  select case when field_hash.key is null or field_hash.value is null then null
    else extensions.hmac(convert_to(lower(regexp_replace(field_hash.value, '\s', '', 'g')), 'UTF8'), decode(field_hash.key, 'base64'), 'sha256')
  end
$$;
revoke execute on function "better_supabase"."field_hash"(text, text) from public, anon, authenticated, service_role;

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

-- The lookup hash of a value under the owner's lookup key, to compare with a
-- <column>_lookup column; null when the owner has no lookup key.
create or replace function "better_supabase"."field_lookup"(owner text, value text)
returns bytea
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if field_lookup.value is null then
    return null;
  end if;
  return "better_supabase"."field_hash"("better_supabase"."field_lookup_key"(field_lookup.owner, false), field_lookup.value);
end;
$$;
revoke execute on function "better_supabase"."field_lookup"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."field_lookup"(text, text) to service_role;

-- Which owners the caller reaches have a data key and a lookup key: their
-- tenants (or themselves) for a signed-in user, every owner with a key for the
-- service role, with when each key was created and the data key last rotated,
-- the app table columns the owner's kind of key encrypts and how many
-- encrypted fields other blocks keep for it. It reads no key material.
create or replace function "better_supabase"."field_key_status"()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
begin
  if (select auth.uid()) is null and not v_service then
    raise exception 'only signed-in users and the service role read field key status' using errcode = '42501', hint = 'FIELD_KEY_STATUS_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'owner', o.owner,
      'has_key', k.id is not null,
      'has_lookup_key', l.id is not null,
      'key_created_at', k.created_at,
      'key_rotated_at', nullif(k.updated_at, k.created_at),
      'lookup_key_created_at', l.created_at,
      'columns', case when o.owner like 'tenant:%' then '[]'::jsonb when o.owner like 'user:%' then '[]'::jsonb when o.owner = 'app' then '[]'::jsonb else '[]'::jsonb end,
      'fields', 0
    ) order by o.owner)
    from (
      select substr(s.name, 14) as owner
      from vault.secrets s
      where v_service and left(s.name, 13) = 'bs:field-key:'
      union
      select 'tenant:' || (m.id)::text
      from better_supabase.member_organization_ids() as m(id)
      where not v_service
    ) o
    left join vault.secrets k on k.name = 'bs:field-key:' || o.owner
    left join vault.secrets l on l.name = 'bs:field-lookup-key:' || o.owner
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."field_key_status"() from public, anon;
grant execute on function "better_supabase"."field_key_status"() to authenticated, service_role;

-- Deletes an owner's data key and lookup key, so every value encrypted with
-- them reads as null and no lookup finds it (crypto-shredding, for example
-- after a tenant is erased).
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
  delete from vault.secrets s where s.name in ('bs:field-key:' || drop_field_key.owner, 'bs:field-lookup-key:' || drop_field_key.owner);
  if not found then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."drop_field_key"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."drop_field_key"(text) to service_role;

-- Replaces the owner's data key with a new one and encrypts every value it
-- protected again, in one transaction: the encrypted app table columns, the
-- columns options.sealed lists and the values other blocks seal. Those tables
-- are locked against writes until it commits, so no value is sealed with the
-- old key meanwhile. The lookup key stays, so lookup hashes don't change.
-- Members rotate their tenant's key with field_encryption.manage.
create or replace function "better_supabase"."rotate_field_key"(owner text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_secret uuid;
  v_old text;
  v_new text;
  v_rows bigint;
  v_values bigint := 0;
begin
  if rotate_field_key.owner is null or length(rotate_field_key.owner) = 0 then
    raise exception 'a field key needs an owner' using errcode = '22023', hint = 'FIELD_KEY_OWNER';
  end if;
  if not coalesce((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))
    or case when rotate_field_key.owner like 'tenant:%' then coalesce(better_supabase.can('tenant', (substr(rotate_field_key.owner, 8))::uuid, 'field_encryption.manage'), false) else false end, false) then
    raise exception 'not allowed to rotate the field key of this owner' using errcode = '42501', hint = 'FIELD_KEY_FORBIDDEN';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('bs:field-key:' || rotate_field_key.owner, 0));
  select ds.id, ds.decrypted_secret into v_secret, v_old from vault.decrypted_secrets ds
  where ds.name = 'bs:field-key:' || rotate_field_key.owner;
  if v_secret is null then
    raise exception 'the owner has no field key' using errcode = 'P0002', hint = 'FIELD_KEY_NOT_FOUND';
  end if;
  v_new := encode(extensions.gen_random_bytes(32), 'base64');
  perform vault.update_secret(v_secret, v_new);
  null;
  return jsonb_build_object('owner', rotate_field_key.owner, 'values', v_values, 'rotated_at', now());
end;
$$;
revoke execute on function "better_supabase"."rotate_field_key"(text) from public, anon;
grant execute on function "better_supabase"."rotate_field_key"(text) to authenticated, service_role;

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_141_field_encryption.sql
-- better-supabase module: field-encryption
-- @bsb-block-data field-encryption
-- @bsb-hash sha256:24e0bcbdcd12ed728d7919648db8a89bd1920454f56ac96aeb81e0e3b7248c21
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pgcrypto" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('field-encryption', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_141_field_encryption.sql
-- better-supabase module: field-encryption
-- @bsb-block field-encryption@2 managed
-- @bsb-hash sha256:bde2afbd3821e01701f16c30d35f1ce2cf5acee8693ca3f1b08eaf2eb8a38786
-- Encrypts app table columns and custom field values at rest with a data key per tenant, user or app, kept in Supabase Vault as bs:field-key:<owner>. Only security definer read paths that check the caller's scope decrypt; a lookup column keeps an HMAC of the value under the owner's lookup key for equality searches; drop_field_key deletes both keys so the values can no longer be read or found. Members read which of their owners have keys, with the key dates and what they encrypt, through field_key_status(), and rotate_field_key replaces a data key and encrypts its values again.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists pgcrypto with schema extensions;

-- Field data keys live only in Vault, one per owner (tenant:<id>, user:<id>
-- or app), as bs:field-key:<owner>, and the lookup keys next to them as
-- bs:field-lookup-key:<owner>. No API role calls field_key, field_lookup_key,
-- field_seal, field_open or field_hash; security definer functions of app
-- tables and custom fields do, after they check the caller's scope.
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

create or replace function "better_supabase"."field_lookup_key"(owner text, make boolean default true)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_key text;
begin
  if field_lookup_key.owner is null or length(field_lookup_key.owner) = 0 then
    raise exception 'a field key needs an owner' using errcode = '22023', hint = 'FIELD_KEY_OWNER';
  end if;
  select ds.decrypted_secret into v_key from vault.decrypted_secrets ds
  where ds.name = 'bs:field-lookup-key:' || field_lookup_key.owner;
  if v_key is not null or not field_lookup_key.make then
    return v_key;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('bs:field-lookup-key:' || field_lookup_key.owner, 0));
  select ds.decrypted_secret into v_key from vault.decrypted_secrets ds
  where ds.name = 'bs:field-lookup-key:' || field_lookup_key.owner;
  if v_key is null then
    v_key := encode(extensions.gen_random_bytes(32), 'base64');
    perform vault.create_secret(v_key, 'bs:field-lookup-key:' || field_lookup_key.owner, 'better-supabase field lookup key');
  end if;
  return v_key;
end;
$$;
revoke execute on function "better_supabase"."field_lookup_key"(text, boolean) from public, anon, authenticated, service_role;

-- Encrypts a value with a data key: bsf1: then base64 of an OpenPGP message.
create or replace function "better_supabase"."field_seal"(key text, value text)
returns text
language sql
volatile
set search_path = ''
as $$
  select case when field_seal.value is null then null
    when left(field_seal.value, 5) = 'bsf1:' then field_seal.value
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

-- The lookup hash of a value: HMAC-SHA256 of the value, lowercased and
-- without whitespace, under a lookup key. null without a key or a value.
create or replace function "better_supabase"."field_hash"(key text, value text)
returns bytea
language sql
immutable
set search_path = ''
as $$
  select case when field_hash.key is null or field_hash.value is null then null
    else extensions.hmac(convert_to(lower(regexp_replace(field_hash.value, '\s', '', 'g')), 'UTF8'), decode(field_hash.key, 'base64'), 'sha256')
  end
$$;
revoke execute on function "better_supabase"."field_hash"(text, text) from public, anon, authenticated, service_role;

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

-- The lookup hash of a value under the owner's lookup key, to compare with a
-- <column>_lookup column; null when the owner has no lookup key.
create or replace function "better_supabase"."field_lookup"(owner text, value text)
returns bytea
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if field_lookup.value is null then
    return null;
  end if;
  return "better_supabase"."field_hash"("better_supabase"."field_lookup_key"(field_lookup.owner, false), field_lookup.value);
end;
$$;
revoke execute on function "better_supabase"."field_lookup"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."field_lookup"(text, text) to service_role;

-- Which owners the caller reaches have a data key and a lookup key: their
-- tenants (or themselves) for a signed-in user, every owner with a key for the
-- service role, with when each key was created and the data key last rotated,
-- the app table columns the owner's kind of key encrypts and how many
-- encrypted fields other blocks keep for it. It reads no key material.
create or replace function "better_supabase"."field_key_status"()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
begin
  if (select auth.uid()) is null and not v_service then
    raise exception 'only signed-in users and the service role read field key status' using errcode = '42501', hint = 'FIELD_KEY_STATUS_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'owner', o.owner,
      'has_key', k.id is not null,
      'has_lookup_key', l.id is not null,
      'key_created_at', k.created_at,
      'key_rotated_at', nullif(k.updated_at, k.created_at),
      'lookup_key_created_at', l.created_at,
      'columns', case when o.owner like 'tenant:%' then '[]'::jsonb when o.owner like 'user:%' then '[]'::jsonb when o.owner = 'app' then '[]'::jsonb else '[]'::jsonb end,
      'fields', coalesce((select count(*) from "better_supabase"."field_definitions" d where d."encrypted" and 'tenant:' || (d."tenant_id")::text = o.owner), 0)
    ) order by o.owner)
    from (
      select substr(s.name, 14) as owner
      from vault.secrets s
      where v_service and left(s.name, 13) = 'bs:field-key:'
      union
      select 'tenant:' || (m.id)::text
      from better_supabase.member_organization_ids() as m(id)
      where not v_service
    ) o
    left join vault.secrets k on k.name = 'bs:field-key:' || o.owner
    left join vault.secrets l on l.name = 'bs:field-lookup-key:' || o.owner
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."field_key_status"() from public, anon;
grant execute on function "better_supabase"."field_key_status"() to authenticated, service_role;

-- Deletes an owner's data key and lookup key, so every value encrypted with
-- them reads as null and no lookup finds it (crypto-shredding, for example
-- after a tenant is erased).
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
  delete from vault.secrets s where s.name in ('bs:field-key:' || drop_field_key.owner, 'bs:field-lookup-key:' || drop_field_key.owner);
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

-- Replaces the owner's data key with a new one and encrypts every value it
-- protected again, in one transaction: the encrypted app table columns, the
-- columns options.sealed lists and the values other blocks seal. Those tables
-- are locked against writes until it commits, so no value is sealed with the
-- old key meanwhile. The lookup key stays, so lookup hashes don't change.
-- Members rotate their tenant's key with field_encryption.manage.
create or replace function "better_supabase"."rotate_field_key"(owner text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_secret uuid;
  v_old text;
  v_new text;
  v_rows bigint;
  v_values bigint := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if rotate_field_key.owner is null or length(rotate_field_key.owner) = 0 then
    raise exception 'a field key needs an owner' using errcode = '22023', hint = 'FIELD_KEY_OWNER';
  end if;
  if not coalesce((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))
    or case when rotate_field_key.owner like 'tenant:%' then coalesce(better_supabase.can('tenant', (substr(rotate_field_key.owner, 8))::uuid, 'field_encryption.manage'), false) else false end, false) then
    raise exception 'not allowed to rotate the field key of this owner' using errcode = '42501', hint = 'FIELD_KEY_FORBIDDEN';
  end if;
  lock table "better_supabase"."field_values" in exclusive mode;
  perform pg_advisory_xact_lock(hashtextextended('bs:field-key:' || rotate_field_key.owner, 0));
  select ds.id, ds.decrypted_secret into v_secret, v_old from vault.decrypted_secrets ds
  where ds.name = 'bs:field-key:' || rotate_field_key.owner;
  if v_secret is null then
    raise exception 'the owner has no field key' using errcode = 'P0002', hint = 'FIELD_KEY_NOT_FOUND';
  end if;
  v_new := encode(extensions.gen_random_bytes(32), 'base64');
  perform vault.update_secret(v_secret, v_new);
  update "better_supabase"."field_values" x set "value_text" = case when left(x."value_text", 5) = 'bsf1:' then "better_supabase"."field_seal"(v_new, "better_supabase"."field_open"(v_old, x."value_text")) else x."value_text" end
  where 'tenant:' || (x."tenant_id")::text = rotate_field_key.owner and (left(x."value_text", 5) = 'bsf1:');
  get diagnostics v_rows = row_count;
  v_values := v_values + v_rows;
  perform "better_supabase".emit_event('field_key.rotated', jsonb_build_object('owner', rotate_field_key.owner, 'values', v_values), 'field-keys/' || rotate_field_key.owner, null, null, 'better-supabase/field-encryption');
  perform better_supabase.audit_event(
    event_type => 'field_key.rotated',
    category => 'security',
    target_type => 'field_key',
    record_id => rotate_field_key.owner,
    metadata => jsonb_build_object('owner', rotate_field_key.owner, 'values', v_values)
  );
  return jsonb_build_object('owner', rotate_field_key.owner, 'values', v_values, 'rotated_at', now());
end;
$$;
revoke execute on function "better_supabase"."rotate_field_key"(text) from public, anon;
grant execute on function "better_supabase"."rotate_field_key"(text) to authenticated, service_role;

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_141_field_encryption.sql
-- better-supabase module: field-encryption
-- @bsb-block-data field-encryption
-- @bsb-hash sha256:24e0bcbdcd12ed728d7919648db8a89bd1920454f56ac96aeb81e0e3b7248c21
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pgcrypto" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('field-encryption', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_141_field_encryption.sql
-- better-supabase module: field-encryption
-- @bsb-block field-encryption@2 managed
-- @bsb-hash sha256:9aa14c8e1f3f5ec62b0a93443f454badfb397f293b947cc6ab98e16593d24e41
-- Encrypts app table columns and custom field values at rest with a data key per tenant, user or app, kept in Supabase Vault as bs:field-key:<owner>. Only security definer read paths that check the caller's scope decrypt; a lookup column keeps an HMAC of the value under the owner's lookup key for equality searches; drop_field_key deletes both keys so the values can no longer be read or found. Members read which of their owners have keys, with the key dates and what they encrypt, through field_key_status(), and rotate_field_key replaces a data key and encrypts its values again.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;
create extension if not exists pgcrypto with schema extensions;

-- Field data keys live only in Vault, one per owner (tenant:<id>, user:<id>
-- or app), as bs:field-key:<owner>, and the lookup keys next to them as
-- bs:field-lookup-key:<owner>. No API role calls field_key, field_lookup_key,
-- field_seal, field_open or field_hash; security definer functions of app
-- tables and custom fields do, after they check the caller's scope.
create or replace function "app_private"."field_key"(owner text, make boolean default true)
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
revoke execute on function "app_private"."field_key"(text, boolean) from public, anon, authenticated, service_role;

create or replace function "app_private"."field_lookup_key"(owner text, make boolean default true)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_key text;
begin
  if field_lookup_key.owner is null or length(field_lookup_key.owner) = 0 then
    raise exception 'a field key needs an owner' using errcode = '22023', hint = 'FIELD_KEY_OWNER';
  end if;
  select ds.decrypted_secret into v_key from vault.decrypted_secrets ds
  where ds.name = 'bs:field-lookup-key:' || field_lookup_key.owner;
  if v_key is not null or not field_lookup_key.make then
    return v_key;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('bs:field-lookup-key:' || field_lookup_key.owner, 0));
  select ds.decrypted_secret into v_key from vault.decrypted_secrets ds
  where ds.name = 'bs:field-lookup-key:' || field_lookup_key.owner;
  if v_key is null then
    v_key := encode(extensions.gen_random_bytes(32), 'base64');
    perform vault.create_secret(v_key, 'bs:field-lookup-key:' || field_lookup_key.owner, 'better-supabase field lookup key');
  end if;
  return v_key;
end;
$$;
revoke execute on function "app_private"."field_lookup_key"(text, boolean) from public, anon, authenticated, service_role;

-- Encrypts a value with a data key: bsf1: then base64 of an OpenPGP message.
create or replace function "app_private"."field_seal"(key text, value text)
returns text
language sql
volatile
set search_path = ''
as $$
  select case when field_seal.value is null then null
    when left(field_seal.value, 5) = 'bsf1:' then field_seal.value
    else 'bsf1:' || translate(encode(extensions.pgp_sym_encrypt(field_seal.value, field_seal.key, 'cipher-algo=aes256, s2k-mode=1'), 'base64'), E'\n', '')
  end
$$;
revoke execute on function "app_private"."field_seal"(text, text) from public, anon, authenticated, service_role;

-- Decrypts a value; a value without the prefix was stored before the column
-- was encrypted and comes back as it is. null when the key is gone.
create or replace function "app_private"."field_open"(key text, value text)
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
revoke execute on function "app_private"."field_open"(text, text) from public, anon, authenticated, service_role;

-- The lookup hash of a value: HMAC-SHA256 of the value, lowercased and
-- without whitespace, under a lookup key. null without a key or a value.
create or replace function "app_private"."field_hash"(key text, value text)
returns bytea
language sql
immutable
set search_path = ''
as $$
  select case when field_hash.key is null or field_hash.value is null then null
    else extensions.hmac(convert_to(lower(regexp_replace(field_hash.value, '\s', '', 'g')), 'UTF8'), decode(field_hash.key, 'base64'), 'sha256')
  end
$$;
revoke execute on function "app_private"."field_hash"(text, text) from public, anon, authenticated, service_role;

-- Encrypts a value with the owner's key, creating the key on first use.
create or replace function "app_private"."field_encrypt"(owner text, value text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
begin
  if field_encrypt.value is null then
    return null;
  end if;
  return "app_private"."field_seal"("app_private"."field_key"(field_encrypt.owner, true), field_encrypt.value);
end;
$$;
revoke execute on function "app_private"."field_encrypt"(text, text) from public, anon, authenticated;
grant execute on function "app_private"."field_encrypt"(text, text) to service_role;

-- Decrypts a value with the owner's key; null when the key was dropped.
create or replace function "app_private"."field_decrypt"(owner text, value text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
begin
  if field_decrypt.value is null then
    return null;
  end if;
  return "app_private"."field_open"("app_private"."field_key"(field_decrypt.owner, false), field_decrypt.value);
end;
$$;
revoke execute on function "app_private"."field_decrypt"(text, text) from public, anon, authenticated;
grant execute on function "app_private"."field_decrypt"(text, text) to service_role;

-- The lookup hash of a value under the owner's lookup key, to compare with a
-- <column>_lookup column; null when the owner has no lookup key.
create or replace function "app_private"."field_lookup"(owner text, value text)
returns bytea
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if field_lookup.value is null then
    return null;
  end if;
  return "app_private"."field_hash"("app_private"."field_lookup_key"(field_lookup.owner, false), field_lookup.value);
end;
$$;
revoke execute on function "app_private"."field_lookup"(text, text) from public, anon, authenticated;
grant execute on function "app_private"."field_lookup"(text, text) to service_role;

-- Which owners the caller reaches have a data key and a lookup key: their
-- tenants (or themselves) for a signed-in user, every owner with a key for the
-- service role, with when each key was created and the data key last rotated,
-- the app table columns the owner's kind of key encrypts and how many
-- encrypted fields other blocks keep for it. It reads no key material.
create or replace function "app_private"."field_key_status"()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
begin
  if (select auth.uid()) is null and not v_service then
    raise exception 'only signed-in users and the service role read field key status' using errcode = '42501', hint = 'FIELD_KEY_STATUS_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'owner', o.owner,
      'has_key', k.id is not null,
      'has_lookup_key', l.id is not null,
      'key_created_at', k.created_at,
      'key_rotated_at', nullif(k.updated_at, k.created_at),
      'lookup_key_created_at', l.created_at,
      'columns', case when o.owner like 'tenant:%' then '[]'::jsonb when o.owner like 'user:%' then '[]'::jsonb when o.owner = 'app' then '[]'::jsonb else '[]'::jsonb end,
      'fields', 0
    ) order by o.owner)
    from (
      select substr(s.name, 14) as owner
      from vault.secrets s
      where v_service and left(s.name, 13) = 'bs:field-key:'
      union
      select 'tenant:' || (m.id)::text
      from better_supabase.member_organization_ids() as m(id)
      where not v_service
    ) o
    left join vault.secrets k on k.name = 'bs:field-key:' || o.owner
    left join vault.secrets l on l.name = 'bs:field-lookup-key:' || o.owner
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "app_private"."field_key_status"() from public, anon;
grant execute on function "app_private"."field_key_status"() to authenticated, service_role;

-- Deletes an owner's data key and lookup key, so every value encrypted with
-- them reads as null and no lookup finds it (crypto-shredding, for example
-- after a tenant is erased).
create or replace function "app_private"."drop_field_key"(owner text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role drops field keys' using errcode = '42501', hint = 'FIELD_KEY_FORBIDDEN';
  end if;
  delete from vault.secrets s where s.name in ('bs:field-key:' || drop_field_key.owner, 'bs:field-lookup-key:' || drop_field_key.owner);
  if not found then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."drop_field_key"(text) from public, anon, authenticated;
grant execute on function "app_private"."drop_field_key"(text) to service_role;

-- Replaces the owner's data key with a new one and encrypts every value it
-- protected again, in one transaction: the encrypted app table columns, the
-- columns options.sealed lists and the values other blocks seal. Those tables
-- are locked against writes until it commits, so no value is sealed with the
-- old key meanwhile. The lookup key stays, so lookup hashes don't change.
-- Members rotate their tenant's key with field_encryption.manage.
create or replace function "app_private"."rotate_field_key"(owner text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_secret uuid;
  v_old text;
  v_new text;
  v_rows bigint;
  v_values bigint := 0;
begin
  if rotate_field_key.owner is null or length(rotate_field_key.owner) = 0 then
    raise exception 'a field key needs an owner' using errcode = '22023', hint = 'FIELD_KEY_OWNER';
  end if;
  if not coalesce((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))
    or case when rotate_field_key.owner like 'tenant:%' then coalesce(better_supabase.can('tenant', (substr(rotate_field_key.owner, 8))::uuid, 'field_encryption.manage'), false) else false end, false) then
    raise exception 'not allowed to rotate the field key of this owner' using errcode = '42501', hint = 'FIELD_KEY_FORBIDDEN';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('bs:field-key:' || rotate_field_key.owner, 0));
  select ds.id, ds.decrypted_secret into v_secret, v_old from vault.decrypted_secrets ds
  where ds.name = 'bs:field-key:' || rotate_field_key.owner;
  if v_secret is null then
    raise exception 'the owner has no field key' using errcode = 'P0002', hint = 'FIELD_KEY_NOT_FOUND';
  end if;
  v_new := encode(extensions.gen_random_bytes(32), 'base64');
  perform vault.update_secret(v_secret, v_new);
  null;
  return jsonb_build_object('owner', rotate_field_key.owner, 'values', v_values, 'rotated_at', now());
end;
$$;
revoke execute on function "app_private"."rotate_field_key"(text) from public, anon;
grant execute on function "app_private"."rotate_field_key"(text) to authenticated, service_role;

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_141_field_encryption.sql
-- better-supabase module: field-encryption
-- @bsb-block-data field-encryption
-- @bsb-hash sha256:24e0bcbdcd12ed728d7919648db8a89bd1920454f56ac96aeb81e0e3b7248c21
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pgcrypto" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('field-encryption', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_141_field_encryption.sql
-- better-supabase module: field-encryption
-- @bsb-block field-encryption@2 managed
-- @bsb-hash sha256:ca69b1f65f0015153fff0240917e11b6116c52195a9fc1ed547f0f4ee03ed8fd
-- Encrypts app table columns and custom field values at rest with a data key per tenant, user or app, kept in Supabase Vault as bs:field-key:<owner>. Only security definer read paths that check the caller's scope decrypt; a lookup column keeps an HMAC of the value under the owner's lookup key for equality searches; drop_field_key deletes both keys so the values can no longer be read or found. Members read which of their owners have keys, with the key dates and what they encrypt, through field_key_status(), and rotate_field_key replaces a data key and encrypts its values again.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists pgcrypto with schema extensions;

-- Field data keys live only in Vault, one per owner (tenant:<id>, user:<id>
-- or app), as bs:field-key:<owner>, and the lookup keys next to them as
-- bs:field-lookup-key:<owner>. No API role calls field_key, field_lookup_key,
-- field_seal, field_open or field_hash; security definer functions of app
-- tables and custom fields do, after they check the caller's scope.
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

create or replace function "better_supabase"."field_lookup_key"(owner text, make boolean default true)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_key text;
begin
  if field_lookup_key.owner is null or length(field_lookup_key.owner) = 0 then
    raise exception 'a field key needs an owner' using errcode = '22023', hint = 'FIELD_KEY_OWNER';
  end if;
  select ds.decrypted_secret into v_key from vault.decrypted_secrets ds
  where ds.name = 'bs:field-lookup-key:' || field_lookup_key.owner;
  if v_key is not null or not field_lookup_key.make then
    return v_key;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('bs:field-lookup-key:' || field_lookup_key.owner, 0));
  select ds.decrypted_secret into v_key from vault.decrypted_secrets ds
  where ds.name = 'bs:field-lookup-key:' || field_lookup_key.owner;
  if v_key is null then
    v_key := encode(extensions.gen_random_bytes(32), 'base64');
    perform vault.create_secret(v_key, 'bs:field-lookup-key:' || field_lookup_key.owner, 'better-supabase field lookup key');
  end if;
  return v_key;
end;
$$;
revoke execute on function "better_supabase"."field_lookup_key"(text, boolean) from public, anon, authenticated, service_role;

-- Encrypts a value with a data key: bsf1: then base64 of an OpenPGP message.
create or replace function "better_supabase"."field_seal"(key text, value text)
returns text
language sql
volatile
set search_path = ''
as $$
  select case when field_seal.value is null then null
    when left(field_seal.value, 5) = 'bsf1:' then field_seal.value
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

-- The lookup hash of a value: HMAC-SHA256 of the value, lowercased and
-- without whitespace, under a lookup key. null without a key or a value.
create or replace function "better_supabase"."field_hash"(key text, value text)
returns bytea
language sql
immutable
set search_path = ''
as $$
  select case when field_hash.key is null or field_hash.value is null then null
    else extensions.hmac(convert_to(lower(regexp_replace(field_hash.value, '\s', '', 'g')), 'UTF8'), decode(field_hash.key, 'base64'), 'sha256')
  end
$$;
revoke execute on function "better_supabase"."field_hash"(text, text) from public, anon, authenticated, service_role;

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

-- The lookup hash of a value under the owner's lookup key, to compare with a
-- <column>_lookup column; null when the owner has no lookup key.
create or replace function "better_supabase"."field_lookup"(owner text, value text)
returns bytea
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if field_lookup.value is null then
    return null;
  end if;
  return "better_supabase"."field_hash"("better_supabase"."field_lookup_key"(field_lookup.owner, false), field_lookup.value);
end;
$$;
revoke execute on function "better_supabase"."field_lookup"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."field_lookup"(text, text) to service_role;

-- Which owners the caller reaches have a data key and a lookup key: their
-- tenants (or themselves) for a signed-in user, every owner with a key for the
-- service role, with when each key was created and the data key last rotated,
-- the app table columns the owner's kind of key encrypts and how many
-- encrypted fields other blocks keep for it. It reads no key material.
create or replace function "better_supabase"."field_key_status"()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
begin
  if (select auth.uid()) is null and not v_service then
    raise exception 'only signed-in users and the service role read field key status' using errcode = '42501', hint = 'FIELD_KEY_STATUS_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'owner', o.owner,
      'has_key', k.id is not null,
      'has_lookup_key', l.id is not null,
      'key_created_at', k.created_at,
      'key_rotated_at', nullif(k.updated_at, k.created_at),
      'lookup_key_created_at', l.created_at,
      'columns', case when o.owner like 'tenant:%' then '[]'::jsonb when o.owner like 'user:%' then '[]'::jsonb when o.owner = 'app' then '[]'::jsonb else '[]'::jsonb end,
      'fields', 0
    ) order by o.owner)
    from (
      select substr(s.name, 14) as owner
      from vault.secrets s
      where v_service and left(s.name, 13) = 'bs:field-key:'
      union
      select 'tenant:' || (m.id)::text
      from better_supabase.member_organization_ids() as m(id)
      where not v_service
    ) o
    left join vault.secrets k on k.name = 'bs:field-key:' || o.owner
    left join vault.secrets l on l.name = 'bs:field-lookup-key:' || o.owner
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."field_key_status"() from public, anon;
grant execute on function "better_supabase"."field_key_status"() to authenticated, service_role;

-- Deletes an owner's data key and lookup key, so every value encrypted with
-- them reads as null and no lookup finds it (crypto-shredding, for example
-- after a tenant is erased).
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
  delete from vault.secrets s where s.name in ('bs:field-key:' || drop_field_key.owner, 'bs:field-lookup-key:' || drop_field_key.owner);
  if not found then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."drop_field_key"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."drop_field_key"(text) to service_role;

-- Replaces the owner's data key with a new one and encrypts every value it
-- protected again, in one transaction: the encrypted app table columns, the
-- columns options.sealed lists and the values other blocks seal. Those tables
-- are locked against writes until it commits, so no value is sealed with the
-- old key meanwhile. The lookup key stays, so lookup hashes don't change.
-- Members rotate their tenant's key with field_encryption.manage.
create or replace function "better_supabase"."rotate_field_key"(owner text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_secret uuid;
  v_old text;
  v_new text;
  v_rows bigint;
  v_values bigint := 0;
begin
  if rotate_field_key.owner is null or length(rotate_field_key.owner) = 0 then
    raise exception 'a field key needs an owner' using errcode = '22023', hint = 'FIELD_KEY_OWNER';
  end if;
  if not coalesce((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))
    or case when rotate_field_key.owner like 'tenant:%' then coalesce(better_supabase.can('tenant', (substr(rotate_field_key.owner, 8))::uuid, 'field_encryption.manage'), false) else false end, false) then
    raise exception 'not allowed to rotate the field key of this owner' using errcode = '42501', hint = 'FIELD_KEY_FORBIDDEN';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('bs:field-key:' || rotate_field_key.owner, 0));
  select ds.id, ds.decrypted_secret into v_secret, v_old from vault.decrypted_secrets ds
  where ds.name = 'bs:field-key:' || rotate_field_key.owner;
  if v_secret is null then
    raise exception 'the owner has no field key' using errcode = 'P0002', hint = 'FIELD_KEY_NOT_FOUND';
  end if;
  v_new := encode(extensions.gen_random_bytes(32), 'base64');
  perform vault.update_secret(v_secret, v_new);
  null;
  return jsonb_build_object('owner', rotate_field_key.owner, 'values', v_values, 'rotated_at', now());
end;
$$;
revoke execute on function "better_supabase"."rotate_field_key"(text) from public, anon;
grant execute on function "better_supabase"."rotate_field_key"(text) to authenticated, service_role;

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

create or replace function "api"."field_lookup"(owner text, value text)
returns bytea
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."field_lookup"($1, $2) $$;
revoke execute on function "api"."field_lookup"(text, text) from public, anon, authenticated;
grant execute on function "api"."field_lookup"(text, text) to service_role;

create or replace function "api"."field_key_status"()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."field_key_status"() $$;
revoke execute on function "api"."field_key_status"() from public, anon;
grant execute on function "api"."field_key_status"() to authenticated, service_role;

create or replace function "api"."drop_field_key"(owner text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drop_field_key"($1) $$;
revoke execute on function "api"."drop_field_key"(text) from public, anon, authenticated;
grant execute on function "api"."drop_field_key"(text) to service_role;

create or replace function "api"."rotate_field_key"(owner text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."rotate_field_key"($1) $$;
revoke execute on function "api"."rotate_field_key"(text) from public, anon;
grant execute on function "api"."rotate_field_key"(text) to authenticated, service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_141_field_encryption.sql
-- better-supabase module: field-encryption
-- @bsb-block-data field-encryption
-- @bsb-hash sha256:24e0bcbdcd12ed728d7919648db8a89bd1920454f56ac96aeb81e0e3b7248c21
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pgcrypto" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('field-encryption', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
