-- ==== alone: schema supabase/schemas/900_better_supabase_104_signing_keys.sql
-- better-supabase module: signing-keys
-- @bsb-block signing-keys@1 managed
-- @bsb-hash sha256:6e6dd3f39b36d610c87c1428e00cca1f52bb8fc02caccb5c8b97cba67895d759
-- Ed25519 or ES256 signing keys per owner: the private JWK in Supabase Vault, one active key per owner, rotation that keeps a retired kid in the JWKS until the latest exp a signer noted, and a purge. Only the service role calls it; createSigningKeys() in better-supabase/blocks/signing-keys generates keys and signs with WebCrypto.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Asymmetric signing keys per owner (a tenant, an app, a stream): the public
-- JWK here, the private JWK in Vault. One key per owner is active; a retired
-- key stays in the JWKS until publish_until, the latest exp a signer noted.
create table if not exists "better_supabase"."signing_keys" (
  "id" uuid primary key default gen_random_uuid(),
  "owner_type" text not null check ("owner_type" ~ '^[a-z][a-z0-9_-]{0,39}$'),
  "owner_id" text not null check (length("owner_id") between 1 and 200),
  "kid" text not null unique check (length("kid") between 1 and 200),
  "alg" text not null check ("alg" in ('Ed25519', 'ES256')),
  "public_jwk" jsonb not null check (not ("public_jwk" ? 'd')),
  "vault_secret_id" uuid not null,
  "state" text not null default 'active' check ("state" in ('active', 'retired')),
  "publish_until" timestamptz,
  "created_at" timestamptz not null default now(),
  "retired_at" timestamptz
);
create unique index if not exists signing_keys_active_idx on "better_supabase"."signing_keys" ("owner_type", "owner_id") where "state" = 'active';
create index if not exists signing_keys_owner_idx on "better_supabase"."signing_keys" ("owner_type", "owner_id", "created_at" desc);
alter table "better_supabase"."signing_keys" enable row level security;
revoke all on "better_supabase"."signing_keys" from anon, authenticated;
grant all on "better_supabase"."signing_keys" to service_role;

-- Adds a key and makes it the owner's active one; the key it replaces is
-- retired and stays published until its last token expires.
create or replace function "better_supabase"."add_signing_key"(owner_type text, owner_id text, kid text, alg text, public_jwk jsonb, private_jwk text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old "better_supabase"."signing_keys";
  v_row "better_supabase"."signing_keys";
  v_vault uuid;
begin
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages signing keys' using errcode = '42501', hint = 'SIGNING_KEYS_FORBIDDEN';
  end if;
  if add_signing_key.private_jwk is null or length(add_signing_key.private_jwk) = 0 then
    raise exception 'a signing key needs its private JWK' using errcode = '22023', hint = 'SIGNING_KEY_INVALID';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'bs:signing:' || add_signing_key.owner_type || ':' || add_signing_key.owner_id, 0));
  update "better_supabase"."signing_keys" k set "state" = 'retired', "retired_at" = now()
  where k."owner_type" = add_signing_key.owner_type
    and k."owner_id" = add_signing_key.owner_id
    and k."state" = 'active'
  returning k.* into v_old;
  v_vault := vault.create_secret(
    add_signing_key.private_jwk,
    'bs:signing:' || add_signing_key.kid,
    'better-supabase signing key'
  );
  insert into "better_supabase"."signing_keys" ("owner_type", "owner_id", "kid", "alg", "public_jwk", "vault_secret_id")
  values (add_signing_key.owner_type, add_signing_key.owner_id, add_signing_key.kid, add_signing_key.alg,
    add_signing_key.public_jwk, v_vault)
  returning * into v_row;
  if v_old."kid" is not null then
    null;
  end if;
  null;
  return jsonb_build_object('kid', v_row."kid", 'alg', v_row."alg", 'retired', v_old."kid");
end;
$$;
revoke execute on function "better_supabase"."add_signing_key"(text, text, text, text, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."add_signing_key"(text, text, text, text, jsonb, text) to service_role;

-- The owner's active key with its private JWK, or null.
create or replace function "better_supabase"."signing_key"(owner_type text, owner_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages signing keys' using errcode = '42501', hint = 'SIGNING_KEYS_FORBIDDEN';
  end if;
  return (
    select jsonb_build_object('kid', k."kid", 'alg', k."alg", 'privateKey', ds.decrypted_secret)
    from "better_supabase"."signing_keys" k
    join vault.decrypted_secrets ds on ds.id = k."vault_secret_id"
    where k."owner_type" = signing_key.owner_type
      and k."owner_id" = signing_key.owner_id
      and k."state" = 'active'
  );
end;
$$;
revoke execute on function "better_supabase"."signing_key"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."signing_key"(text, text) to service_role;

-- Keeps the key published until at least exp; false for an unknown kid.
create or replace function "better_supabase"."note_signing_key_exp"(kid text, exp timestamptz)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages signing keys' using errcode = '42501', hint = 'SIGNING_KEYS_FORBIDDEN';
  end if;
  update "better_supabase"."signing_keys" k set "publish_until" = note_signing_key_exp.exp
  where k."kid" = note_signing_key_exp.kid
    and (k."publish_until" is null or k."publish_until" < note_signing_key_exp.exp);
  return exists (select 1 from "better_supabase"."signing_keys" k where k."kid" = note_signing_key_exp.kid);
end;
$$;
revoke execute on function "better_supabase"."note_signing_key_exp"(text, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."note_signing_key_exp"(text, timestamptz) to service_role;

-- Retires a key without a replacement; false when it was not active.
create or replace function "better_supabase"."retire_signing_key"(kid text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."signing_keys";
begin
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages signing keys' using errcode = '42501', hint = 'SIGNING_KEYS_FORBIDDEN';
  end if;
  update "better_supabase"."signing_keys" k set "state" = 'retired', "retired_at" = now()
  where k."kid" = retire_signing_key.kid and k."state" = 'active'
  returning k.* into v_row;
  if v_row."kid" is null then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."retire_signing_key"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."retire_signing_key"(text) to service_role;

-- The owner's JWK Set: the active key and every retired key still in use.
create or replace function "better_supabase"."signing_jwks"(owner_type text, owner_id text, grace interval default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages signing keys' using errcode = '42501', hint = 'SIGNING_KEYS_FORBIDDEN';
  end if;
  return jsonb_build_object('keys', coalesce((
    select jsonb_agg(k."public_jwk" || jsonb_build_object('kid', k."kid", 'use', 'sig')
      order by k."created_at" desc)
    from "better_supabase"."signing_keys" k
    where k."owner_type" = signing_jwks.owner_type
      and k."owner_id" = signing_jwks.owner_id
      and (k."state" = 'active' or k."publish_until" + coalesce(grace, '5 minutes'::interval) > now())
  ), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."signing_jwks"(text, text, interval) from public, anon, authenticated;
grant execute on function "better_supabase"."signing_jwks"(text, text, interval) to service_role;

-- Deletes every key of an owner, for example from on_organization_purge.
create or replace function "better_supabase"."delete_signing_keys"(owner_type text, owner_id text)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages signing keys' using errcode = '42501', hint = 'SIGNING_KEYS_FORBIDDEN';
  end if;
  delete from "better_supabase"."signing_keys" k
  where k."owner_type" = delete_signing_keys.owner_type
    and k."owner_id" = delete_signing_keys.owner_id;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."delete_signing_keys"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."delete_signing_keys"(text, text) to service_role;

-- Deletes retired keys no token can still need.
create or replace function "better_supabase"."purge_signing_keys"(grace interval default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages signing keys' using errcode = '42501', hint = 'SIGNING_KEYS_FORBIDDEN';
  end if;
  delete from "better_supabase"."signing_keys" k
  where k."state" = 'retired' and not (k."state" = 'active' or k."publish_until" + coalesce(grace, '5 minutes'::interval) > now());
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."purge_signing_keys"(interval) from public, anon, authenticated;
grant execute on function "better_supabase"."purge_signing_keys"(interval) to service_role;

-- Deleting a key deletes its Vault secret.
create or replace function "better_supabase"."drop_signing_key_vault_secret"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from vault.secrets vs where vs.id = old."vault_secret_id";
  return null;
end;
$$;
revoke execute on function "better_supabase"."drop_signing_key_vault_secret"() from public, anon, authenticated;
drop trigger if exists "bsb_signing_key_vault" on "better_supabase"."signing_keys";
create trigger "bsb_signing_key_vault" after delete on "better_supabase"."signing_keys"
  for each row execute function "better_supabase"."drop_signing_key_vault_secret"();

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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_104_signing_keys.sql
-- better-supabase module: signing-keys
-- @bsb-block-data signing-keys
-- @bsb-hash sha256:edd36d64344238d41ca12d081d7d72ae73b18d9c79c7478b69dccbc76885ff2d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('signing-keys', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_104_signing_keys.sql
-- better-supabase module: signing-keys
-- @bsb-block signing-keys@1 managed
-- @bsb-hash sha256:0ae1be98a383c3aa4d1c3ff3b7be0a2f1e484a23d034d97f9fa0f80bf3ea7e60
-- Ed25519 or ES256 signing keys per owner: the private JWK in Supabase Vault, one active key per owner, rotation that keeps a retired kid in the JWKS until the latest exp a signer noted, and a purge. Only the service role calls it; createSigningKeys() in better-supabase/blocks/signing-keys generates keys and signs with WebCrypto.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Asymmetric signing keys per owner (a tenant, an app, a stream): the public
-- JWK here, the private JWK in Vault. One key per owner is active; a retired
-- key stays in the JWKS until publish_until, the latest exp a signer noted.
create table if not exists "better_supabase"."signing_keys" (
  "id" uuid primary key default gen_random_uuid(),
  "owner_type" text not null check ("owner_type" ~ '^[a-z][a-z0-9_-]{0,39}$'),
  "owner_id" text not null check (length("owner_id") between 1 and 200),
  "kid" text not null unique check (length("kid") between 1 and 200),
  "alg" text not null check ("alg" in ('Ed25519', 'ES256')),
  "public_jwk" jsonb not null check (not ("public_jwk" ? 'd')),
  "vault_secret_id" uuid not null,
  "state" text not null default 'active' check ("state" in ('active', 'retired')),
  "publish_until" timestamptz,
  "created_at" timestamptz not null default now(),
  "retired_at" timestamptz
);
create unique index if not exists signing_keys_active_idx on "better_supabase"."signing_keys" ("owner_type", "owner_id") where "state" = 'active';
create index if not exists signing_keys_owner_idx on "better_supabase"."signing_keys" ("owner_type", "owner_id", "created_at" desc);
alter table "better_supabase"."signing_keys" enable row level security;
revoke all on "better_supabase"."signing_keys" from anon, authenticated;
grant all on "better_supabase"."signing_keys" to service_role;

-- Adds a key and makes it the owner's active one; the key it replaces is
-- retired and stays published until its last token expires.
create or replace function "better_supabase"."add_signing_key"(owner_type text, owner_id text, kid text, alg text, public_jwk jsonb, private_jwk text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old "better_supabase"."signing_keys";
  v_row "better_supabase"."signing_keys";
  v_vault uuid;
begin
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages signing keys' using errcode = '42501', hint = 'SIGNING_KEYS_FORBIDDEN';
  end if;
  if add_signing_key.private_jwk is null or length(add_signing_key.private_jwk) = 0 then
    raise exception 'a signing key needs its private JWK' using errcode = '22023', hint = 'SIGNING_KEY_INVALID';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'bs:signing:' || add_signing_key.owner_type || ':' || add_signing_key.owner_id, 0));
  update "better_supabase"."signing_keys" k set "state" = 'retired', "retired_at" = now()
  where k."owner_type" = add_signing_key.owner_type
    and k."owner_id" = add_signing_key.owner_id
    and k."state" = 'active'
  returning k.* into v_old;
  v_vault := vault.create_secret(
    add_signing_key.private_jwk,
    'bs:signing:' || add_signing_key.kid,
    'better-supabase signing key'
  );
  insert into "better_supabase"."signing_keys" ("owner_type", "owner_id", "kid", "alg", "public_jwk", "vault_secret_id")
  values (add_signing_key.owner_type, add_signing_key.owner_id, add_signing_key.kid, add_signing_key.alg,
    add_signing_key.public_jwk, v_vault)
  returning * into v_row;
  if v_old."kid" is not null then
    perform "better_supabase".emit_event('signing_key.retired', jsonb_build_object('ownerType', v_old."owner_type", 'ownerId', v_old."owner_id", 'kid', v_old."kid"), 'signing-keys/' || v_old."kid", null, null, 'better-supabase/signing-keys');
  perform better_supabase.audit_event(
    event_type => 'signing_key.retired',
    category => 'security',
    target_type => 'signing_key',
    record_id => v_old."kid",
    metadata => jsonb_build_object('ownerType', v_old."owner_type", 'ownerId', v_old."owner_id", 'kid', v_old."kid")
  );
  end if;
  perform "better_supabase".emit_event('signing_key.created', jsonb_build_object('ownerType', v_row."owner_type", 'ownerId', v_row."owner_id", 'kid', v_row."kid", 'alg', v_row."alg"), 'signing-keys/' || v_row."kid", null, null, 'better-supabase/signing-keys');
  perform better_supabase.audit_event(
    event_type => 'signing_key.created',
    category => 'security',
    target_type => 'signing_key',
    record_id => v_row."kid",
    metadata => jsonb_build_object('ownerType', v_row."owner_type", 'ownerId', v_row."owner_id", 'kid', v_row."kid", 'alg', v_row."alg")
  );
  return jsonb_build_object('kid', v_row."kid", 'alg', v_row."alg", 'retired', v_old."kid");
end;
$$;
revoke execute on function "better_supabase"."add_signing_key"(text, text, text, text, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."add_signing_key"(text, text, text, text, jsonb, text) to service_role;

-- The owner's active key with its private JWK, or null.
create or replace function "better_supabase"."signing_key"(owner_type text, owner_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages signing keys' using errcode = '42501', hint = 'SIGNING_KEYS_FORBIDDEN';
  end if;
  return (
    select jsonb_build_object('kid', k."kid", 'alg', k."alg", 'privateKey', ds.decrypted_secret)
    from "better_supabase"."signing_keys" k
    join vault.decrypted_secrets ds on ds.id = k."vault_secret_id"
    where k."owner_type" = signing_key.owner_type
      and k."owner_id" = signing_key.owner_id
      and k."state" = 'active'
  );
end;
$$;
revoke execute on function "better_supabase"."signing_key"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."signing_key"(text, text) to service_role;

-- Keeps the key published until at least exp; false for an unknown kid.
create or replace function "better_supabase"."note_signing_key_exp"(kid text, exp timestamptz)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages signing keys' using errcode = '42501', hint = 'SIGNING_KEYS_FORBIDDEN';
  end if;
  update "better_supabase"."signing_keys" k set "publish_until" = note_signing_key_exp.exp
  where k."kid" = note_signing_key_exp.kid
    and (k."publish_until" is null or k."publish_until" < note_signing_key_exp.exp);
  return exists (select 1 from "better_supabase"."signing_keys" k where k."kid" = note_signing_key_exp.kid);
end;
$$;
revoke execute on function "better_supabase"."note_signing_key_exp"(text, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."note_signing_key_exp"(text, timestamptz) to service_role;

-- Retires a key without a replacement; false when it was not active.
create or replace function "better_supabase"."retire_signing_key"(kid text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."signing_keys";
begin
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages signing keys' using errcode = '42501', hint = 'SIGNING_KEYS_FORBIDDEN';
  end if;
  update "better_supabase"."signing_keys" k set "state" = 'retired', "retired_at" = now()
  where k."kid" = retire_signing_key.kid and k."state" = 'active'
  returning k.* into v_row;
  if v_row."kid" is null then
    return false;
  end if;
  perform "better_supabase".emit_event('signing_key.retired', jsonb_build_object('ownerType', v_row."owner_type", 'ownerId', v_row."owner_id", 'kid', v_row."kid"), 'signing-keys/' || v_row."kid", null, null, 'better-supabase/signing-keys');
  perform better_supabase.audit_event(
    event_type => 'signing_key.retired',
    category => 'security',
    target_type => 'signing_key',
    record_id => v_row."kid",
    metadata => jsonb_build_object('ownerType', v_row."owner_type", 'ownerId', v_row."owner_id", 'kid', v_row."kid")
  );
  return true;
end;
$$;
revoke execute on function "better_supabase"."retire_signing_key"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."retire_signing_key"(text) to service_role;

-- The owner's JWK Set: the active key and every retired key still in use.
create or replace function "better_supabase"."signing_jwks"(owner_type text, owner_id text, grace interval default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages signing keys' using errcode = '42501', hint = 'SIGNING_KEYS_FORBIDDEN';
  end if;
  return jsonb_build_object('keys', coalesce((
    select jsonb_agg(k."public_jwk" || jsonb_build_object('kid', k."kid", 'use', 'sig')
      order by k."created_at" desc)
    from "better_supabase"."signing_keys" k
    where k."owner_type" = signing_jwks.owner_type
      and k."owner_id" = signing_jwks.owner_id
      and (k."state" = 'active' or k."publish_until" + coalesce(grace, '5 minutes'::interval) > now())
  ), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."signing_jwks"(text, text, interval) from public, anon, authenticated;
grant execute on function "better_supabase"."signing_jwks"(text, text, interval) to service_role;

-- Deletes every key of an owner, for example from on_organization_purge.
create or replace function "better_supabase"."delete_signing_keys"(owner_type text, owner_id text)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages signing keys' using errcode = '42501', hint = 'SIGNING_KEYS_FORBIDDEN';
  end if;
  delete from "better_supabase"."signing_keys" k
  where k."owner_type" = delete_signing_keys.owner_type
    and k."owner_id" = delete_signing_keys.owner_id;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."delete_signing_keys"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."delete_signing_keys"(text, text) to service_role;

-- Deletes retired keys no token can still need.
create or replace function "better_supabase"."purge_signing_keys"(grace interval default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages signing keys' using errcode = '42501', hint = 'SIGNING_KEYS_FORBIDDEN';
  end if;
  delete from "better_supabase"."signing_keys" k
  where k."state" = 'retired' and not (k."state" = 'active' or k."publish_until" + coalesce(grace, '5 minutes'::interval) > now());
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."purge_signing_keys"(interval) from public, anon, authenticated;
grant execute on function "better_supabase"."purge_signing_keys"(interval) to service_role;

-- Deleting a key deletes its Vault secret.
create or replace function "better_supabase"."drop_signing_key_vault_secret"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from vault.secrets vs where vs.id = old."vault_secret_id";
  return null;
end;
$$;
revoke execute on function "better_supabase"."drop_signing_key_vault_secret"() from public, anon, authenticated;
drop trigger if exists "bsb_signing_key_vault" on "better_supabase"."signing_keys";
create trigger "bsb_signing_key_vault" after delete on "better_supabase"."signing_keys"
  for each row execute function "better_supabase"."drop_signing_key_vault_secret"();

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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_104_signing_keys.sql
-- better-supabase module: signing-keys
-- @bsb-block-data signing-keys
-- @bsb-hash sha256:edd36d64344238d41ca12d081d7d72ae73b18d9c79c7478b69dccbc76885ff2d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('signing-keys', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_104_signing_keys.sql
-- better-supabase module: signing-keys
-- @bsb-block signing-keys@1 managed
-- @bsb-hash sha256:d2ebe51eacd3d707b43093d1848a3ad9c8961fbe47aa59602597e9cf047ad3a8
-- Ed25519 or ES256 signing keys per owner: the private JWK in Supabase Vault, one active key per owner, rotation that keeps a retired kid in the JWKS until the latest exp a signer noted, and a purge. Only the service role calls it; createSigningKeys() in better-supabase/blocks/signing-keys generates keys and signs with WebCrypto.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
-- Asymmetric signing keys per owner (a tenant, an app, a stream): the public
-- JWK here, the private JWK in Vault. One key per owner is active; a retired
-- key stays in the JWKS until publish_until, the latest exp a signer noted.
create table if not exists "app_private"."signing_keys" (
  "id" uuid primary key default gen_random_uuid(),
  "owner_type" text not null check ("owner_type" ~ '^[a-z][a-z0-9_-]{0,39}$'),
  "owner_id" text not null check (length("owner_id") between 1 and 200),
  "kid" text not null unique check (length("kid") between 1 and 200),
  "alg" text not null check ("alg" in ('Ed25519', 'ES256')),
  "public_jwk" jsonb not null check (not ("public_jwk" ? 'd')),
  "vault_secret_id" uuid not null,
  "state" text not null default 'active' check ("state" in ('active', 'retired')),
  "publish_until" timestamptz,
  "created_at" timestamptz not null default now(),
  "retired_at" timestamptz
);
create unique index if not exists signing_keys_active_idx on "app_private"."signing_keys" ("owner_type", "owner_id") where "state" = 'active';
create index if not exists signing_keys_owner_idx on "app_private"."signing_keys" ("owner_type", "owner_id", "created_at" desc);
alter table "app_private"."signing_keys" enable row level security;
revoke all on "app_private"."signing_keys" from anon, authenticated;
grant all on "app_private"."signing_keys" to service_role;

-- Adds a key and makes it the owner's active one; the key it replaces is
-- retired and stays published until its last token expires.
create or replace function "app_private"."add_signing_key"(owner_type text, owner_id text, kid text, alg text, public_jwk jsonb, private_jwk text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old "app_private"."signing_keys";
  v_row "app_private"."signing_keys";
  v_vault uuid;
begin
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages signing keys' using errcode = '42501', hint = 'SIGNING_KEYS_FORBIDDEN';
  end if;
  if add_signing_key.private_jwk is null or length(add_signing_key.private_jwk) = 0 then
    raise exception 'a signing key needs its private JWK' using errcode = '22023', hint = 'SIGNING_KEY_INVALID';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'bs:signing:' || add_signing_key.owner_type || ':' || add_signing_key.owner_id, 0));
  update "app_private"."signing_keys" k set "state" = 'retired', "retired_at" = now()
  where k."owner_type" = add_signing_key.owner_type
    and k."owner_id" = add_signing_key.owner_id
    and k."state" = 'active'
  returning k.* into v_old;
  v_vault := vault.create_secret(
    add_signing_key.private_jwk,
    'bs:signing:' || add_signing_key.kid,
    'better-supabase signing key'
  );
  insert into "app_private"."signing_keys" ("owner_type", "owner_id", "kid", "alg", "public_jwk", "vault_secret_id")
  values (add_signing_key.owner_type, add_signing_key.owner_id, add_signing_key.kid, add_signing_key.alg,
    add_signing_key.public_jwk, v_vault)
  returning * into v_row;
  if v_old."kid" is not null then
    null;
  end if;
  null;
  return jsonb_build_object('kid', v_row."kid", 'alg', v_row."alg", 'retired', v_old."kid");
end;
$$;
revoke execute on function "app_private"."add_signing_key"(text, text, text, text, jsonb, text) from public, anon, authenticated;
grant execute on function "app_private"."add_signing_key"(text, text, text, text, jsonb, text) to service_role;

-- The owner's active key with its private JWK, or null.
create or replace function "app_private"."signing_key"(owner_type text, owner_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages signing keys' using errcode = '42501', hint = 'SIGNING_KEYS_FORBIDDEN';
  end if;
  return (
    select jsonb_build_object('kid', k."kid", 'alg', k."alg", 'privateKey', ds.decrypted_secret)
    from "app_private"."signing_keys" k
    join vault.decrypted_secrets ds on ds.id = k."vault_secret_id"
    where k."owner_type" = signing_key.owner_type
      and k."owner_id" = signing_key.owner_id
      and k."state" = 'active'
  );
end;
$$;
revoke execute on function "app_private"."signing_key"(text, text) from public, anon, authenticated;
grant execute on function "app_private"."signing_key"(text, text) to service_role;

-- Keeps the key published until at least exp; false for an unknown kid.
create or replace function "app_private"."note_signing_key_exp"(kid text, exp timestamptz)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages signing keys' using errcode = '42501', hint = 'SIGNING_KEYS_FORBIDDEN';
  end if;
  update "app_private"."signing_keys" k set "publish_until" = note_signing_key_exp.exp
  where k."kid" = note_signing_key_exp.kid
    and (k."publish_until" is null or k."publish_until" < note_signing_key_exp.exp);
  return exists (select 1 from "app_private"."signing_keys" k where k."kid" = note_signing_key_exp.kid);
end;
$$;
revoke execute on function "app_private"."note_signing_key_exp"(text, timestamptz) from public, anon, authenticated;
grant execute on function "app_private"."note_signing_key_exp"(text, timestamptz) to service_role;

-- Retires a key without a replacement; false when it was not active.
create or replace function "app_private"."retire_signing_key"(kid text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."signing_keys";
begin
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages signing keys' using errcode = '42501', hint = 'SIGNING_KEYS_FORBIDDEN';
  end if;
  update "app_private"."signing_keys" k set "state" = 'retired', "retired_at" = now()
  where k."kid" = retire_signing_key.kid and k."state" = 'active'
  returning k.* into v_row;
  if v_row."kid" is null then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."retire_signing_key"(text) from public, anon, authenticated;
grant execute on function "app_private"."retire_signing_key"(text) to service_role;

-- The owner's JWK Set: the active key and every retired key still in use.
create or replace function "app_private"."signing_jwks"(owner_type text, owner_id text, grace interval default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages signing keys' using errcode = '42501', hint = 'SIGNING_KEYS_FORBIDDEN';
  end if;
  return jsonb_build_object('keys', coalesce((
    select jsonb_agg(k."public_jwk" || jsonb_build_object('kid', k."kid", 'use', 'sig')
      order by k."created_at" desc)
    from "app_private"."signing_keys" k
    where k."owner_type" = signing_jwks.owner_type
      and k."owner_id" = signing_jwks.owner_id
      and (k."state" = 'active' or k."publish_until" + coalesce(grace, '5 minutes'::interval) > now())
  ), '[]'::jsonb));
end;
$$;
revoke execute on function "app_private"."signing_jwks"(text, text, interval) from public, anon, authenticated;
grant execute on function "app_private"."signing_jwks"(text, text, interval) to service_role;

-- Deletes every key of an owner, for example from on_organization_purge.
create or replace function "app_private"."delete_signing_keys"(owner_type text, owner_id text)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages signing keys' using errcode = '42501', hint = 'SIGNING_KEYS_FORBIDDEN';
  end if;
  delete from "app_private"."signing_keys" k
  where k."owner_type" = delete_signing_keys.owner_type
    and k."owner_id" = delete_signing_keys.owner_id;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "app_private"."delete_signing_keys"(text, text) from public, anon, authenticated;
grant execute on function "app_private"."delete_signing_keys"(text, text) to service_role;

-- Deletes retired keys no token can still need.
create or replace function "app_private"."purge_signing_keys"(grace interval default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages signing keys' using errcode = '42501', hint = 'SIGNING_KEYS_FORBIDDEN';
  end if;
  delete from "app_private"."signing_keys" k
  where k."state" = 'retired' and not (k."state" = 'active' or k."publish_until" + coalesce(grace, '5 minutes'::interval) > now());
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "app_private"."purge_signing_keys"(interval) from public, anon, authenticated;
grant execute on function "app_private"."purge_signing_keys"(interval) to service_role;

-- Deleting a key deletes its Vault secret.
create or replace function "app_private"."drop_signing_key_vault_secret"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from vault.secrets vs where vs.id = old."vault_secret_id";
  return null;
end;
$$;
revoke execute on function "app_private"."drop_signing_key_vault_secret"() from public, anon, authenticated;
drop trigger if exists "bsb_signing_key_vault" on "app_private"."signing_keys";
create trigger "bsb_signing_key_vault" after delete on "app_private"."signing_keys"
  for each row execute function "app_private"."drop_signing_key_vault_secret"();

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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_104_signing_keys.sql
-- better-supabase module: signing-keys
-- @bsb-block-data signing-keys
-- @bsb-hash sha256:edd36d64344238d41ca12d081d7d72ae73b18d9c79c7478b69dccbc76885ff2d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('signing-keys', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_104_signing_keys.sql
-- better-supabase module: signing-keys
-- @bsb-block signing-keys@1 managed
-- @bsb-hash sha256:24808d5da05b9819f561be2abe96f8c2bef6b9b2321fe423a7c095969c63aa75
-- Ed25519 or ES256 signing keys per owner: the private JWK in Supabase Vault, one active key per owner, rotation that keeps a retired kid in the JWKS until the latest exp a signer noted, and a purge. Only the service role calls it; createSigningKeys() in better-supabase/blocks/signing-keys generates keys and signs with WebCrypto.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Asymmetric signing keys per owner (a tenant, an app, a stream): the public
-- JWK here, the private JWK in Vault. One key per owner is active; a retired
-- key stays in the JWKS until publish_until, the latest exp a signer noted.
create table if not exists "better_supabase"."signing_keys" (
  "id" uuid primary key default gen_random_uuid(),
  "owner_type" text not null check ("owner_type" ~ '^[a-z][a-z0-9_-]{0,39}$'),
  "owner_id" text not null check (length("owner_id") between 1 and 200),
  "kid" text not null unique check (length("kid") between 1 and 200),
  "alg" text not null check ("alg" in ('Ed25519', 'ES256')),
  "public_jwk" jsonb not null check (not ("public_jwk" ? 'd')),
  "vault_secret_id" uuid not null,
  "state" text not null default 'active' check ("state" in ('active', 'retired')),
  "publish_until" timestamptz,
  "created_at" timestamptz not null default now(),
  "retired_at" timestamptz
);
create unique index if not exists signing_keys_active_idx on "better_supabase"."signing_keys" ("owner_type", "owner_id") where "state" = 'active';
create index if not exists signing_keys_owner_idx on "better_supabase"."signing_keys" ("owner_type", "owner_id", "created_at" desc);
alter table "better_supabase"."signing_keys" enable row level security;
revoke all on "better_supabase"."signing_keys" from anon, authenticated;
grant all on "better_supabase"."signing_keys" to service_role;

-- Adds a key and makes it the owner's active one; the key it replaces is
-- retired and stays published until its last token expires.
create or replace function "better_supabase"."add_signing_key"(owner_type text, owner_id text, kid text, alg text, public_jwk jsonb, private_jwk text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old "better_supabase"."signing_keys";
  v_row "better_supabase"."signing_keys";
  v_vault uuid;
begin
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages signing keys' using errcode = '42501', hint = 'SIGNING_KEYS_FORBIDDEN';
  end if;
  if add_signing_key.private_jwk is null or length(add_signing_key.private_jwk) = 0 then
    raise exception 'a signing key needs its private JWK' using errcode = '22023', hint = 'SIGNING_KEY_INVALID';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'bs:signing:' || add_signing_key.owner_type || ':' || add_signing_key.owner_id, 0));
  update "better_supabase"."signing_keys" k set "state" = 'retired', "retired_at" = now()
  where k."owner_type" = add_signing_key.owner_type
    and k."owner_id" = add_signing_key.owner_id
    and k."state" = 'active'
  returning k.* into v_old;
  v_vault := vault.create_secret(
    add_signing_key.private_jwk,
    'bs:signing:' || add_signing_key.kid,
    'better-supabase signing key'
  );
  insert into "better_supabase"."signing_keys" ("owner_type", "owner_id", "kid", "alg", "public_jwk", "vault_secret_id")
  values (add_signing_key.owner_type, add_signing_key.owner_id, add_signing_key.kid, add_signing_key.alg,
    add_signing_key.public_jwk, v_vault)
  returning * into v_row;
  if v_old."kid" is not null then
    null;
  end if;
  null;
  return jsonb_build_object('kid', v_row."kid", 'alg', v_row."alg", 'retired', v_old."kid");
end;
$$;
revoke execute on function "better_supabase"."add_signing_key"(text, text, text, text, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."add_signing_key"(text, text, text, text, jsonb, text) to service_role;

-- The owner's active key with its private JWK, or null.
create or replace function "better_supabase"."signing_key"(owner_type text, owner_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages signing keys' using errcode = '42501', hint = 'SIGNING_KEYS_FORBIDDEN';
  end if;
  return (
    select jsonb_build_object('kid', k."kid", 'alg', k."alg", 'privateKey', ds.decrypted_secret)
    from "better_supabase"."signing_keys" k
    join vault.decrypted_secrets ds on ds.id = k."vault_secret_id"
    where k."owner_type" = signing_key.owner_type
      and k."owner_id" = signing_key.owner_id
      and k."state" = 'active'
  );
end;
$$;
revoke execute on function "better_supabase"."signing_key"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."signing_key"(text, text) to service_role;

-- Keeps the key published until at least exp; false for an unknown kid.
create or replace function "better_supabase"."note_signing_key_exp"(kid text, exp timestamptz)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages signing keys' using errcode = '42501', hint = 'SIGNING_KEYS_FORBIDDEN';
  end if;
  update "better_supabase"."signing_keys" k set "publish_until" = note_signing_key_exp.exp
  where k."kid" = note_signing_key_exp.kid
    and (k."publish_until" is null or k."publish_until" < note_signing_key_exp.exp);
  return exists (select 1 from "better_supabase"."signing_keys" k where k."kid" = note_signing_key_exp.kid);
end;
$$;
revoke execute on function "better_supabase"."note_signing_key_exp"(text, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."note_signing_key_exp"(text, timestamptz) to service_role;

-- Retires a key without a replacement; false when it was not active.
create or replace function "better_supabase"."retire_signing_key"(kid text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."signing_keys";
begin
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages signing keys' using errcode = '42501', hint = 'SIGNING_KEYS_FORBIDDEN';
  end if;
  update "better_supabase"."signing_keys" k set "state" = 'retired', "retired_at" = now()
  where k."kid" = retire_signing_key.kid and k."state" = 'active'
  returning k.* into v_row;
  if v_row."kid" is null then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."retire_signing_key"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."retire_signing_key"(text) to service_role;

-- The owner's JWK Set: the active key and every retired key still in use.
create or replace function "better_supabase"."signing_jwks"(owner_type text, owner_id text, grace interval default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages signing keys' using errcode = '42501', hint = 'SIGNING_KEYS_FORBIDDEN';
  end if;
  return jsonb_build_object('keys', coalesce((
    select jsonb_agg(k."public_jwk" || jsonb_build_object('kid', k."kid", 'use', 'sig')
      order by k."created_at" desc)
    from "better_supabase"."signing_keys" k
    where k."owner_type" = signing_jwks.owner_type
      and k."owner_id" = signing_jwks.owner_id
      and (k."state" = 'active' or k."publish_until" + coalesce(grace, '5 minutes'::interval) > now())
  ), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."signing_jwks"(text, text, interval) from public, anon, authenticated;
grant execute on function "better_supabase"."signing_jwks"(text, text, interval) to service_role;

-- Deletes every key of an owner, for example from on_organization_purge.
create or replace function "better_supabase"."delete_signing_keys"(owner_type text, owner_id text)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages signing keys' using errcode = '42501', hint = 'SIGNING_KEYS_FORBIDDEN';
  end if;
  delete from "better_supabase"."signing_keys" k
  where k."owner_type" = delete_signing_keys.owner_type
    and k."owner_id" = delete_signing_keys.owner_id;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."delete_signing_keys"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."delete_signing_keys"(text, text) to service_role;

-- Deletes retired keys no token can still need.
create or replace function "better_supabase"."purge_signing_keys"(grace interval default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages signing keys' using errcode = '42501', hint = 'SIGNING_KEYS_FORBIDDEN';
  end if;
  delete from "better_supabase"."signing_keys" k
  where k."state" = 'retired' and not (k."state" = 'active' or k."publish_until" + coalesce(grace, '5 minutes'::interval) > now());
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."purge_signing_keys"(interval) from public, anon, authenticated;
grant execute on function "better_supabase"."purge_signing_keys"(interval) to service_role;

-- Deleting a key deletes its Vault secret.
create or replace function "better_supabase"."drop_signing_key_vault_secret"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from vault.secrets vs where vs.id = old."vault_secret_id";
  return null;
end;
$$;
revoke execute on function "better_supabase"."drop_signing_key_vault_secret"() from public, anon, authenticated;
drop trigger if exists "bsb_signing_key_vault" on "better_supabase"."signing_keys";
create trigger "bsb_signing_key_vault" after delete on "better_supabase"."signing_keys"
  for each row execute function "better_supabase"."drop_signing_key_vault_secret"();

-- blocks.signing-keys.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."add_signing_key"(owner_type text, owner_id text, kid text, alg text, public_jwk jsonb, private_jwk text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."add_signing_key"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."add_signing_key"(text, text, text, text, jsonb, text) from public, anon, authenticated;
grant execute on function "api"."add_signing_key"(text, text, text, text, jsonb, text) to service_role;

create or replace function "api"."signing_key"(owner_type text, owner_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."signing_key"($1, $2) $$;
revoke execute on function "api"."signing_key"(text, text) from public, anon, authenticated;
grant execute on function "api"."signing_key"(text, text) to service_role;

create or replace function "api"."note_signing_key_exp"(kid text, exp timestamptz)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."note_signing_key_exp"($1, $2) $$;
revoke execute on function "api"."note_signing_key_exp"(text, timestamptz) from public, anon, authenticated;
grant execute on function "api"."note_signing_key_exp"(text, timestamptz) to service_role;

create or replace function "api"."retire_signing_key"(kid text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."retire_signing_key"($1) $$;
revoke execute on function "api"."retire_signing_key"(text) from public, anon, authenticated;
grant execute on function "api"."retire_signing_key"(text) to service_role;

create or replace function "api"."signing_jwks"(owner_type text, owner_id text, grace interval default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."signing_jwks"($1, $2, $3) $$;
revoke execute on function "api"."signing_jwks"(text, text, interval) from public, anon, authenticated;
grant execute on function "api"."signing_jwks"(text, text, interval) to service_role;

create or replace function "api"."delete_signing_keys"(owner_type text, owner_id text)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_signing_keys"($1, $2) $$;
revoke execute on function "api"."delete_signing_keys"(text, text) from public, anon, authenticated;
grant execute on function "api"."delete_signing_keys"(text, text) to service_role;

create or replace function "api"."purge_signing_keys"(grace interval default null)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."purge_signing_keys"($1) $$;
revoke execute on function "api"."purge_signing_keys"(interval) from public, anon, authenticated;
grant execute on function "api"."purge_signing_keys"(interval) to service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_104_signing_keys.sql
-- better-supabase module: signing-keys
-- @bsb-block-data signing-keys
-- @bsb-hash sha256:edd36d64344238d41ca12d081d7d72ae73b18d9c79c7478b69dccbc76885ff2d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('signing-keys', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_104_signing_keys.sql
-- better-supabase module: signing-keys
-- @bsb-block signing-keys@1 managed
-- @bsb-hash sha256:fe10a479c50e9c06fe96baee81386ab2a0816569c9cb0ceacaf60b3e599e82d4
-- Ed25519 or ES256 signing keys per owner: the private JWK in Supabase Vault, one active key per owner, rotation that keeps a retired kid in the JWKS until the latest exp a signer noted, and a purge. Only the service role calls it; createSigningKeys() in better-supabase/blocks/signing-keys generates keys and signs with WebCrypto.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.as_column_type(value text, target anyelement)
returns anyelement
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return value;
end;
$$;
revoke execute on function better_supabase.as_column_type(text, anyelement) from public;
grant execute on function better_supabase.as_column_type(text, anyelement) to anon, authenticated, service_role;
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Asymmetric signing keys per owner (a tenant, an app, a stream): the public
-- JWK here, the private JWK in Vault. One key per owner is active; a retired
-- key stays in the JWKS until publish_until, the latest exp a signer noted.
-- better_supabase.signing_keys is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."signing_keys" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."signing_keys" add column if not exists "owner_type" text check ("owner_type" ~ '^[a-z][a-z0-9_-]{0,39}$');
alter table "better_supabase"."signing_keys" add column if not exists "owner_id" text check (length("owner_id") between 1 and 200);
alter table "better_supabase"."signing_keys" add column if not exists "kid" text check (length("kid") between 1 and 200);
alter table "better_supabase"."signing_keys" add column if not exists "alg" text check ("alg" in ('Ed25519', 'ES256'));
alter table "better_supabase"."signing_keys" add column if not exists "public_jwk" jsonb check (not ("public_jwk" ? 'd'));
alter table "better_supabase"."signing_keys" add column if not exists "vault_secret_id" uuid;
alter table "better_supabase"."signing_keys" add column if not exists "state" text not null default 'active' check ("state" in ('active', 'retired'));
alter table "better_supabase"."signing_keys" add column if not exists "publish_until" timestamptz;
alter table "better_supabase"."signing_keys" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."signing_keys" add column if not exists "retired_at" timestamptz;
create unique index if not exists signing_keys_active_idx on "better_supabase"."signing_keys" ("owner_type", "owner_id") where "state" = 'active';
create index if not exists signing_keys_owner_idx on "better_supabase"."signing_keys" ("owner_type", "owner_id", "created_at" desc);
alter table "better_supabase"."signing_keys" enable row level security;
grant all on "better_supabase"."signing_keys" to service_role;

-- Adds a key and makes it the owner's active one; the key it replaces is
-- retired and stays published until its last token expires.
create or replace function "better_supabase"."add_signing_key"(owner_type text, owner_id text, kid text, alg text, public_jwk jsonb, private_jwk text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old "better_supabase"."signing_keys";
  v_row "better_supabase"."signing_keys";
  v_vault uuid;
begin
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages signing keys' using errcode = '42501', hint = 'SIGNING_KEYS_FORBIDDEN';
  end if;
  if add_signing_key.private_jwk is null or length(add_signing_key.private_jwk) = 0 then
    raise exception 'a signing key needs its private JWK' using errcode = '22023', hint = 'SIGNING_KEY_INVALID';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'bs:signing:' || add_signing_key.owner_type || ':' || add_signing_key.owner_id, 0));
  update "better_supabase"."signing_keys" k set "state" = better_supabase.as_column_type('retired', (null::"better_supabase"."signing_keys")."state"), "retired_at" = now()
  where k."owner_type" = add_signing_key.owner_type
    and k."owner_id" = add_signing_key.owner_id
    and k."state" = 'active'
  returning k.* into v_old;
  v_vault := vault.create_secret(
    add_signing_key.private_jwk,
    'bs:signing:' || add_signing_key.kid,
    'better-supabase signing key'
  );
  insert into "better_supabase"."signing_keys" ("owner_type", "owner_id", "kid", "alg", "public_jwk", "vault_secret_id")
  values (add_signing_key.owner_type, add_signing_key.owner_id, add_signing_key.kid, better_supabase.as_column_type(add_signing_key.alg, (null::"better_supabase"."signing_keys")."alg"),
    add_signing_key.public_jwk, v_vault)
  returning * into v_row;
  if v_old."kid" is not null then
    null;
  end if;
  null;
  return jsonb_build_object('kid', v_row."kid", 'alg', v_row."alg", 'retired', v_old."kid");
end;
$$;
revoke execute on function "better_supabase"."add_signing_key"(text, text, text, text, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."add_signing_key"(text, text, text, text, jsonb, text) to service_role;

-- The owner's active key with its private JWK, or null.
create or replace function "better_supabase"."signing_key"(owner_type text, owner_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages signing keys' using errcode = '42501', hint = 'SIGNING_KEYS_FORBIDDEN';
  end if;
  return (
    select jsonb_build_object('kid', k."kid", 'alg', k."alg", 'privateKey', ds.decrypted_secret)
    from "better_supabase"."signing_keys" k
    join vault.decrypted_secrets ds on ds.id = k."vault_secret_id"
    where k."owner_type" = signing_key.owner_type
      and k."owner_id" = signing_key.owner_id
      and k."state" = 'active'
  );
end;
$$;
revoke execute on function "better_supabase"."signing_key"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."signing_key"(text, text) to service_role;

-- Keeps the key published until at least exp; false for an unknown kid.
create or replace function "better_supabase"."note_signing_key_exp"(kid text, exp timestamptz)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages signing keys' using errcode = '42501', hint = 'SIGNING_KEYS_FORBIDDEN';
  end if;
  update "better_supabase"."signing_keys" k set "publish_until" = note_signing_key_exp.exp
  where k."kid" = note_signing_key_exp.kid
    and (k."publish_until" is null or k."publish_until" < note_signing_key_exp.exp);
  return exists (select 1 from "better_supabase"."signing_keys" k where k."kid" = note_signing_key_exp.kid);
end;
$$;
revoke execute on function "better_supabase"."note_signing_key_exp"(text, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."note_signing_key_exp"(text, timestamptz) to service_role;

-- Retires a key without a replacement; false when it was not active.
create or replace function "better_supabase"."retire_signing_key"(kid text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."signing_keys";
begin
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages signing keys' using errcode = '42501', hint = 'SIGNING_KEYS_FORBIDDEN';
  end if;
  update "better_supabase"."signing_keys" k set "state" = better_supabase.as_column_type('retired', (null::"better_supabase"."signing_keys")."state"), "retired_at" = now()
  where k."kid" = retire_signing_key.kid and k."state" = 'active'
  returning k.* into v_row;
  if v_row."kid" is null then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."retire_signing_key"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."retire_signing_key"(text) to service_role;

-- The owner's JWK Set: the active key and every retired key still in use.
create or replace function "better_supabase"."signing_jwks"(owner_type text, owner_id text, grace interval default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages signing keys' using errcode = '42501', hint = 'SIGNING_KEYS_FORBIDDEN';
  end if;
  return jsonb_build_object('keys', coalesce((
    select jsonb_agg(k."public_jwk" || jsonb_build_object('kid', k."kid", 'use', 'sig')
      order by k."created_at" desc)
    from "better_supabase"."signing_keys" k
    where k."owner_type" = signing_jwks.owner_type
      and k."owner_id" = signing_jwks.owner_id
      and (k."state" = 'active' or k."publish_until" + coalesce(grace, '5 minutes'::interval) > now())
  ), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."signing_jwks"(text, text, interval) from public, anon, authenticated;
grant execute on function "better_supabase"."signing_jwks"(text, text, interval) to service_role;

-- Deletes every key of an owner, for example from on_organization_purge.
create or replace function "better_supabase"."delete_signing_keys"(owner_type text, owner_id text)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages signing keys' using errcode = '42501', hint = 'SIGNING_KEYS_FORBIDDEN';
  end if;
  delete from "better_supabase"."signing_keys" k
  where k."owner_type" = delete_signing_keys.owner_type
    and k."owner_id" = delete_signing_keys.owner_id;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."delete_signing_keys"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."delete_signing_keys"(text, text) to service_role;

-- Deletes retired keys no token can still need.
create or replace function "better_supabase"."purge_signing_keys"(grace interval default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages signing keys' using errcode = '42501', hint = 'SIGNING_KEYS_FORBIDDEN';
  end if;
  delete from "better_supabase"."signing_keys" k
  where k."state" = 'retired' and not (k."state" = 'active' or k."publish_until" + coalesce(grace, '5 minutes'::interval) > now());
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."purge_signing_keys"(interval) from public, anon, authenticated;
grant execute on function "better_supabase"."purge_signing_keys"(interval) to service_role;

-- Deleting a key deletes its Vault secret.
create or replace function "better_supabase"."drop_signing_key_vault_secret"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from vault.secrets vs where vs.id = old."vault_secret_id";
  return null;
end;
$$;
revoke execute on function "better_supabase"."drop_signing_key_vault_secret"() from public, anon, authenticated;
drop trigger if exists "bsb_signing_key_vault" on "better_supabase"."signing_keys";
create trigger "bsb_signing_key_vault" after delete on "better_supabase"."signing_keys"
  for each row execute function "better_supabase"."drop_signing_key_vault_secret"();

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

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_104_signing_keys.sql
-- better-supabase module: signing-keys
-- @bsb-block-data signing-keys
-- @bsb-hash sha256:edd36d64344238d41ca12d081d7d72ae73b18d9c79c7478b69dccbc76885ff2d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('signing-keys', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
