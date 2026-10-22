-- ==== alone: schema supabase/schemas/900_better_supabase_27_webhooks_in.sql
-- better-supabase module: webhooks-in
-- @bs-module webhooks-in@4 managed
-- Per-tenant trigger URLs with a hashed token, optional Standard Webhooks or HMAC verification, a body size limit, receive counters and the last status; deliveries go to the webhook inbox with the endpoint's tenant.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Trigger URLs a tenant hands to another system: /hooks/<token> stores each
-- delivery in the webhook inbox (source webhook-in), with the endpoint's
-- tenant. Only the token's hash is kept, and the signing secret is a Vault
-- secret (secret_id) unless options.secretStorage is "column".
create table if not exists "better_supabase"."incoming_webhooks" (
  id uuid primary key default gen_random_uuid(),
  tenant uuid not null,
  name text not null,
  token_hash text not null unique,
  verify text not null default 'none' check (verify in ('none', 'standard-webhooks', 'hmac-sha256', 'shared-secret')),
  secret text,
  secret_id uuid,
  previous_secret text,
  previous_secret_id uuid,
  previous_secret_expires_at timestamptz,
  signature_header text,
  enabled boolean not null default true,
  max_body_bytes integer not null default 1048576 check (max_body_bytes > 0),
  receive_count bigint not null default 0,
  last_received_at timestamptz,
  last_status integer,
  metadata jsonb not null default '{}',
  subject_type text check (subject_type ~ '^[a-z][a-z0-9_]{0,62}$'),
  subject_id text check (length(subject_id) between 1 and 200),
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table "better_supabase"."incoming_webhooks" add column if not exists subject_type text check (subject_type ~ '^[a-z][a-z0-9_]{0,62}$');
alter table "better_supabase"."incoming_webhooks" add column if not exists subject_id text check (length(subject_id) between 1 and 200);
alter table "better_supabase"."incoming_webhooks" add column if not exists secret_id uuid;
alter table "better_supabase"."incoming_webhooks" drop constraint if exists incoming_webhooks_verify_check;
alter table "better_supabase"."incoming_webhooks" add constraint incoming_webhooks_verify_check check (verify in ('none', 'standard-webhooks', 'hmac-sha256', 'shared-secret'));
alter table "better_supabase"."incoming_webhooks" add column if not exists previous_secret text;
alter table "better_supabase"."incoming_webhooks" add column if not exists previous_secret_id uuid;
alter table "better_supabase"."incoming_webhooks" add column if not exists previous_secret_expires_at timestamptz;
create index if not exists incoming_webhooks_tenant_idx on "better_supabase"."incoming_webhooks" (tenant);
create index if not exists incoming_webhooks_subject_idx on "better_supabase"."incoming_webhooks" (tenant, subject_type, subject_id);
create index if not exists incoming_webhooks_created_by_idx on "better_supabase"."incoming_webhooks" (created_by) where created_by is not null;
alter table "better_supabase"."incoming_webhooks" add column if not exists updated_at timestamptz not null default now();
drop trigger if exists bsb_updated_at on "better_supabase"."incoming_webhooks";
create trigger bsb_updated_at before update on "better_supabase"."incoming_webhooks"
  for each row execute function better_supabase.set_updated_at('updated_at');
-- Deleting an endpoint (or its tenant or subject) deletes its Vault secret.
create or replace function "better_supabase"."drop_incoming_webhook_secret"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from vault.secrets vs where vs.id in (old."secret_id", old."previous_secret_id");
  return null;
end;
$$;
revoke execute on function "better_supabase"."drop_incoming_webhook_secret"() from public, anon, authenticated;
drop trigger if exists "bsb_incoming_webhook_vault" on "better_supabase"."incoming_webhooks";
create trigger "bsb_incoming_webhook_vault" after delete on "better_supabase"."incoming_webhooks"
  for each row when (old."secret_id" is not null or old."previous_secret_id" is not null) execute function "better_supabase"."drop_incoming_webhook_secret"();
alter table "better_supabase"."incoming_webhooks" enable row level security;
revoke all on "better_supabase"."incoming_webhooks" from anon, authenticated;
-- The secret stays with the service: members read every other column.
grant select (id, tenant, name, verify, signature_header, enabled, max_body_bytes, receive_count, last_received_at, last_status, metadata, subject_type, subject_id, created_by, created_at, updated_at) on "better_supabase"."incoming_webhooks" to authenticated;
grant all on "better_supabase"."incoming_webhooks" to service_role;

create or replace function "better_supabase"."incoming_webhook_tenant_ids"()
returns setof uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return query select better_supabase.tenant_ids_with('webhooks.read');
end;
$$;
revoke execute on function "better_supabase"."incoming_webhook_tenant_ids"() from public, anon;
grant execute on function "better_supabase"."incoming_webhook_tenant_ids"() to authenticated, service_role;
-- Whether the caller may read an endpoint's subject: its row is visible to
-- them (the subject table's own policies apply) and they hold its permission.
create or replace function "better_supabase"."incoming_webhook_subject_readable"(subject_type text, subject_id text, tenant uuid)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select subject_type is null or true
$$;
revoke execute on function "better_supabase"."incoming_webhook_subject_readable"(text, text, uuid) from public, anon;
grant execute on function "better_supabase"."incoming_webhook_subject_readable"(text, text, uuid) to authenticated, service_role;

drop policy if exists bsb_incoming_webhooks_read on "better_supabase"."incoming_webhooks";
create policy bsb_incoming_webhooks_read on "better_supabase"."incoming_webhooks" for select to authenticated
  using (
    tenant in (select "better_supabase"."incoming_webhook_tenant_ids"())
    and "better_supabase"."incoming_webhook_subject_readable"(subject_type, subject_id, tenant)
  );

-- A tenant's endpoints, or one subject's, without secrets; runs as the caller.
create or replace function "better_supabase"."list_incoming_webhooks"(tenant uuid, subject_type text default null, subject_id text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', e."id",
    'tenant', e."tenant",
    'name', e."name",
    'verify', e."verify",
    'signature_header', e."signature_header",
    'enabled', e."enabled",
    'max_body_bytes', e."max_body_bytes",
    'receive_count', e."receive_count",
    'last_received_at', e."last_received_at",
    'last_status', e."last_status",
    'metadata', e."metadata",
    'subject_type', e."subject_type",
    'subject_id', e."subject_id",
    'created_by', e."created_by",
    'created_at', e."created_at"
  ) order by e."created_at"), '[]'::jsonb)
  from "better_supabase"."incoming_webhooks" e
  where e."tenant" = list_incoming_webhooks.tenant
    and (list_incoming_webhooks.subject_type is null or e."subject_type" = list_incoming_webhooks.subject_type)
    and (list_incoming_webhooks.subject_id is null or e."subject_id" = list_incoming_webhooks.subject_id)
$$;
revoke execute on function "better_supabase"."list_incoming_webhooks"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."list_incoming_webhooks"(uuid, text, text) to authenticated, service_role;

drop function if exists "better_supabase"."create_incoming_webhook"(uuid, text, text, jsonb, text);
-- Creates an endpoint and returns it with its token (and the signing secret
-- for standard-webhooks and hmac-sha256), shown once.
create or replace function "better_supabase"."create_incoming_webhook"(
  tenant uuid,
  name text,
  verify text default 'none',
  metadata jsonb default '{}',
  signature_header text default null,
  subject_type text default null,
  subject_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid := gen_random_uuid();
  token text := encode(extensions.gen_random_bytes(24), 'hex');
  secret text := case verify
    when 'standard-webhooks' then 'whsec_' || encode(extensions.gen_random_bytes(32), 'base64')
    when 'hmac-sha256' then encode(extensions.gen_random_bytes(32), 'hex')
    when 'shared-secret' then encode(extensions.gen_random_bytes(32), 'hex')
  end;
  created "better_supabase"."incoming_webhooks";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), tenant, 'webhooks.manage'), false)) then
    raise exception 'Not allowed to manage incoming webhooks' using errcode = '42501', hint = 'WEBHOOK_IN_FORBIDDEN';
  end if;
  if verify not in ('none', 'standard-webhooks', 'hmac-sha256', 'shared-secret') then
    raise exception 'Unknown verification mode' using errcode = '22023', hint = 'WEBHOOK_IN_VERIFY_UNKNOWN';
  end if;
  if (subject_type is null) <> (subject_id is null) then
    raise exception 'Pass subject_type and subject_id together' using errcode = '22023', hint = 'WEBHOOK_IN_SUBJECT_INVALID';
  end if;
  if subject_type is not null and not (true) then
    raise exception 'No such subject in this tenant' using errcode = '22023', hint = 'WEBHOOK_IN_SUBJECT_INVALID';
  end if;
  insert into "better_supabase"."incoming_webhooks" ("id", "tenant", "name", "token_hash", "verify", "secret", "secret_id", "signature_header", "metadata", "subject_type", "subject_id", "created_by")
  values (v_id,
    tenant,
    name,
    encode(extensions.digest(token, 'sha256'), 'hex'),
    verify,
    null,
    case when secret is null then null else vault.create_secret(secret, 'webhook-in:' || v_id::text || ':' || gen_random_uuid()::text, 'better-supabase incoming webhook secret') end,
    case verify
      when 'hmac-sha256' then coalesce(signature_header, null, 'x-signature')
      when 'shared-secret' then coalesce(signature_header, null, 'x-webhook-secret')
    end,
    coalesce(metadata, '{}'),
    subject_type,
    subject_id,
    auth.uid())
  returning * into created;
  null;
  return jsonb_build_object('id', created."id", 'tenant', created."tenant", 'name', created."name",
    'verify', created."verify", 'token', token, 'secret', secret, 'signatureHeader', created."signature_header",
    'subjectType', created."subject_type", 'subjectId', created."subject_id");
end;
$$;

-- A new token (the old URL stops working); with rotate_secret, a new secret too.
create or replace function "better_supabase"."rotate_incoming_webhook"(endpoint uuid, rotate_secret boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  token text := encode(extensions.gen_random_bytes(24), 'hex');
  v_secret text;
  updated "better_supabase"."incoming_webhooks";
  previous "better_supabase"."incoming_webhooks";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into previous from "better_supabase"."incoming_webhooks" e where e."id" = endpoint for update;
  if previous."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), previous."tenant", 'webhooks.manage'), false)) then
    raise exception 'No incoming webhook %', endpoint using errcode = 'P0002', hint = 'WEBHOOK_IN_NOT_FOUND';
  end if;
  if rotate_secret then
    v_secret := case previous."verify"
    when 'standard-webhooks' then 'whsec_' || encode(extensions.gen_random_bytes(32), 'base64')
    when 'hmac-sha256' then encode(extensions.gen_random_bytes(32), 'hex')
    when 'shared-secret' then encode(extensions.gen_random_bytes(32), 'hex')
  end;
  end if;
  update "better_supabase"."incoming_webhooks" e set "token_hash" = encode(extensions.digest(token, 'sha256'), 'hex'),
    "secret" = case when rotate_secret then null else e."secret" end,
    "secret_id" = case when rotate_secret then case when v_secret is null then null else vault.create_secret(v_secret, 'webhook-in:' || e."id"::text || ':' || gen_random_uuid()::text, 'better-supabase incoming webhook secret') end else e."secret_id" end,
    "previous_secret" = case when rotate_secret then null else e."previous_secret" end,
    "previous_secret_id" = case when rotate_secret then null else e."previous_secret_id" end,
    "previous_secret_expires_at" = case when rotate_secret then null else e."previous_secret_expires_at" end
  where e."id" = endpoint
  returning * into updated;
  if rotate_secret then
    delete from vault.secrets vs where vs.id in (previous."secret_id", previous."previous_secret_id");
  end if;
  null;
  return jsonb_build_object('id', updated."id", 'token', token, 'secret', v_secret);
end;
$$;

create or replace function "better_supabase"."rotate_incoming_webhook_secret"(endpoint uuid, grace interval default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  previous "better_supabase"."incoming_webhooks";
  updated "better_supabase"."incoming_webhooks";
  v_secret text;
  v_keep boolean := coalesce(grace > interval '0', false);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into previous from "better_supabase"."incoming_webhooks" e where e."id" = endpoint for update;
  if previous."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), previous."tenant", 'webhooks.manage'), false)) then
    raise exception 'No incoming webhook %', endpoint using errcode = 'P0002', hint = 'WEBHOOK_IN_NOT_FOUND';
  end if;
  v_secret := case previous."verify"
    when 'standard-webhooks' then 'whsec_' || encode(extensions.gen_random_bytes(32), 'base64')
    when 'hmac-sha256' then encode(extensions.gen_random_bytes(32), 'hex')
    when 'shared-secret' then encode(extensions.gen_random_bytes(32), 'hex')
  end;
  if v_secret is null then
    raise exception 'This endpoint verifies no secret' using errcode = '22023', hint = 'WEBHOOK_IN_NO_SECRET';
  end if;
  update "better_supabase"."incoming_webhooks" e set
    "secret" = null,
    "secret_id" = case when v_secret is null then null else vault.create_secret(v_secret, 'webhook-in:' || e."id"::text || ':' || gen_random_uuid()::text, 'better-supabase incoming webhook secret') end,
    "previous_secret" = case when v_keep then e."secret" end,
    "previous_secret_id" = case when v_keep then e."secret_id" end,
    "previous_secret_expires_at" = case when v_keep then now() + grace end
  where e."id" = endpoint
  returning * into updated;
  delete from vault.secrets vs
  where vs.id = previous."previous_secret_id" or (not v_keep and vs.id = previous."secret_id");
  null;
  return jsonb_build_object('id', updated."id", 'secret', v_secret, 'previousSecretExpiresAt', updated."previous_secret_expires_at");
end;
$$;

create or replace function "better_supabase"."update_incoming_webhook"(
  endpoint uuid,
  name text default null,
  metadata jsonb default null,
  verify text default null,
  signature_header text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  previous "better_supabase"."incoming_webhooks";
  updated "better_supabase"."incoming_webhooks";
  v_verify text;
  v_secret text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into previous from "better_supabase"."incoming_webhooks" e where e."id" = endpoint for update;
  if previous."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), previous."tenant", 'webhooks.manage'), false)) then
    raise exception 'No incoming webhook %', endpoint using errcode = 'P0002', hint = 'WEBHOOK_IN_NOT_FOUND';
  end if;
  if name is not null and btrim(name) = '' then
    raise exception 'An endpoint needs a name' using errcode = '22023', hint = 'WEBHOOK_IN_NAME_REQUIRED';
  end if;
  if metadata is not null and jsonb_typeof(metadata) <> 'object' then
    raise exception 'metadata must be a JSON object' using errcode = '22023', hint = 'WEBHOOK_IN_METADATA_INVALID';
  end if;
  v_verify := coalesce(verify, previous."verify");
  if v_verify not in ('none', 'standard-webhooks', 'hmac-sha256', 'shared-secret') then
    raise exception 'Unknown verification mode' using errcode = '22023', hint = 'WEBHOOK_IN_VERIFY_UNKNOWN';
  end if;
  if v_verify <> previous."verify" then
    v_secret := case v_verify
    when 'standard-webhooks' then 'whsec_' || encode(extensions.gen_random_bytes(32), 'base64')
    when 'hmac-sha256' then encode(extensions.gen_random_bytes(32), 'hex')
    when 'shared-secret' then encode(extensions.gen_random_bytes(32), 'hex')
  end;
  end if;
  update "better_supabase"."incoming_webhooks" e set
    "name" = coalesce(update_incoming_webhook.name, e."name"),
    "metadata" = coalesce(update_incoming_webhook.metadata, e."metadata"),
    "verify" = v_verify,
    "secret" = case when v_verify = previous."verify" then e."secret" else null end,
    "secret_id" = case when v_verify = previous."verify" then e."secret_id" else case when v_secret is null then null else vault.create_secret(v_secret, 'webhook-in:' || e."id"::text || ':' || gen_random_uuid()::text, 'better-supabase incoming webhook secret') end end,
    "previous_secret" = case when v_verify = previous."verify" then e."previous_secret" end,
    "previous_secret_id" = case when v_verify = previous."verify" then e."previous_secret_id" end,
    "previous_secret_expires_at" = case when v_verify = previous."verify" then e."previous_secret_expires_at" end,
    "signature_header" = case v_verify
      when 'hmac-sha256' then coalesce(update_incoming_webhook.signature_header, case when v_verify = previous."verify" then e."signature_header" end, 'x-signature')
      when 'shared-secret' then coalesce(update_incoming_webhook.signature_header, case when v_verify = previous."verify" then e."signature_header" end, 'x-webhook-secret')
    end
  where e."id" = endpoint
  returning * into updated;
  if v_verify <> previous."verify" then
    delete from vault.secrets vs where vs.id in (previous."secret_id", previous."previous_secret_id");
  end if;
  null;
  return jsonb_build_object('id', updated."id", 'tenant', updated."tenant", 'name', updated."name",
    'verify', updated."verify", 'secret', v_secret, 'signatureHeader', updated."signature_header",
    'metadata', updated."metadata");
end;
$$;

create or replace function "better_supabase"."set_incoming_webhook_enabled"(endpoint uuid, enabled boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select e."tenant" into tenant from "better_supabase"."incoming_webhooks" e where e."id" = endpoint;
  if tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), tenant, 'webhooks.manage'), false)) then
    return false;
  end if;
  update "better_supabase"."incoming_webhooks" e set "enabled" = set_incoming_webhook_enabled.enabled where e."id" = endpoint;
  null;
  return true;
end;
$$;

create or replace function "better_supabase"."delete_incoming_webhook"(endpoint uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select e."tenant" into tenant from "better_supabase"."incoming_webhooks" e where e."id" = endpoint;
  if tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), tenant, 'webhooks.manage'), false)) then
    return false;
  end if;
  delete from "better_supabase"."incoming_webhooks" e where e."id" = endpoint;
  null;
  return true;
end;
$$;

-- The endpoint behind a token, with its secret and metadata, for the
-- receiving route.
drop function if exists "better_supabase"."incoming_webhook_by_token"(text);
create or replace function "better_supabase"."incoming_webhook_by_token"(token text)
returns table (id uuid, tenant text, enabled boolean, verify text, secret text, signature_header text, max_body_bytes integer, previous_secret text, metadata jsonb)
language sql
stable
security definer
set search_path = ''
as $$
  select e."id", e."tenant"::text, e."enabled", e."verify", coalesce(ds.decrypted_secret, e."secret"), e."signature_header", e."max_body_bytes",
    case when e."previous_secret_expires_at" > now() then coalesce(dp.decrypted_secret, e."previous_secret") end, e."metadata"
  from "better_supabase"."incoming_webhooks" e
  left join vault.decrypted_secrets ds on ds.id = e."secret_id"
  left join vault.decrypted_secrets dp on dp.id = e."previous_secret_id"
  where e."token_hash" = encode(extensions.digest(incoming_webhook_by_token.token, 'sha256'), 'hex')
$$;

-- Counts a delivery and keeps its HTTP status.
create or replace function "better_supabase"."record_incoming_webhook"(endpoint uuid, status integer)
returns void
language sql
security definer
set search_path = ''
as $$
  update "better_supabase"."incoming_webhooks" e
  set "receive_count" = e."receive_count" + 1, "last_received_at" = now(), "last_status" = record_incoming_webhook.status
  where e."id" = endpoint
$$;

revoke execute on function "better_supabase"."create_incoming_webhook"(uuid, text, text, jsonb, text, text, text) from public, anon;
grant execute on function "better_supabase"."create_incoming_webhook"(uuid, text, text, jsonb, text, text, text) to authenticated, service_role;
revoke execute on function "better_supabase"."rotate_incoming_webhook"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."rotate_incoming_webhook"(uuid, boolean) to authenticated, service_role;
revoke execute on function "better_supabase"."rotate_incoming_webhook_secret"(uuid, interval) from public, anon;
grant execute on function "better_supabase"."rotate_incoming_webhook_secret"(uuid, interval) to authenticated, service_role;
revoke execute on function "better_supabase"."update_incoming_webhook"(uuid, text, jsonb, text, text) from public, anon;
grant execute on function "better_supabase"."update_incoming_webhook"(uuid, text, jsonb, text, text) to authenticated, service_role;
revoke execute on function "better_supabase"."set_incoming_webhook_enabled"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."set_incoming_webhook_enabled"(uuid, boolean) to authenticated, service_role;
revoke execute on function "better_supabase"."delete_incoming_webhook"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_incoming_webhook"(uuid) to authenticated, service_role;
revoke execute on function "better_supabase"."incoming_webhook_by_token"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."incoming_webhook_by_token"(text) to service_role;
revoke execute on function "better_supabase"."record_incoming_webhook"(uuid, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."record_incoming_webhook"(uuid, integer) to service_role;

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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_27_webhooks_in.sql
-- better-supabase module: webhooks-in
-- @bs-module-data webhooks-in
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('webhooks-in', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_27_webhooks_in.sql
-- better-supabase module: webhooks-in
-- @bs-module webhooks-in@4 managed
-- Per-tenant trigger URLs with a hashed token, optional Standard Webhooks or HMAC verification, a body size limit, receive counters and the last status; deliveries go to the webhook inbox with the endpoint's tenant.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Trigger URLs a tenant hands to another system: /hooks/<token> stores each
-- delivery in the webhook inbox (source webhook-in), with the endpoint's
-- tenant. Only the token's hash is kept, and the signing secret is a Vault
-- secret (secret_id) unless options.secretStorage is "column".
create table if not exists "better_supabase"."incoming_webhooks" (
  id uuid primary key default gen_random_uuid(),
  tenant uuid not null,
  name text not null,
  token_hash text not null unique,
  verify text not null default 'none' check (verify in ('none', 'standard-webhooks', 'hmac-sha256', 'shared-secret')),
  secret text,
  secret_id uuid,
  previous_secret text,
  previous_secret_id uuid,
  previous_secret_expires_at timestamptz,
  signature_header text,
  enabled boolean not null default true,
  max_body_bytes integer not null default 1048576 check (max_body_bytes > 0),
  receive_count bigint not null default 0,
  last_received_at timestamptz,
  last_status integer,
  metadata jsonb not null default '{}',
  subject_type text check (subject_type ~ '^[a-z][a-z0-9_]{0,62}$'),
  subject_id text check (length(subject_id) between 1 and 200),
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table "better_supabase"."incoming_webhooks" add column if not exists subject_type text check (subject_type ~ '^[a-z][a-z0-9_]{0,62}$');
alter table "better_supabase"."incoming_webhooks" add column if not exists subject_id text check (length(subject_id) between 1 and 200);
alter table "better_supabase"."incoming_webhooks" add column if not exists secret_id uuid;
alter table "better_supabase"."incoming_webhooks" drop constraint if exists incoming_webhooks_verify_check;
alter table "better_supabase"."incoming_webhooks" add constraint incoming_webhooks_verify_check check (verify in ('none', 'standard-webhooks', 'hmac-sha256', 'shared-secret'));
alter table "better_supabase"."incoming_webhooks" add column if not exists previous_secret text;
alter table "better_supabase"."incoming_webhooks" add column if not exists previous_secret_id uuid;
alter table "better_supabase"."incoming_webhooks" add column if not exists previous_secret_expires_at timestamptz;
create index if not exists incoming_webhooks_tenant_idx on "better_supabase"."incoming_webhooks" (tenant);
create index if not exists incoming_webhooks_subject_idx on "better_supabase"."incoming_webhooks" (tenant, subject_type, subject_id);
create index if not exists incoming_webhooks_created_by_idx on "better_supabase"."incoming_webhooks" (created_by) where created_by is not null;
alter table "better_supabase"."incoming_webhooks" add column if not exists updated_at timestamptz not null default now();
drop trigger if exists bsb_updated_at on "better_supabase"."incoming_webhooks";
create trigger bsb_updated_at before update on "better_supabase"."incoming_webhooks"
  for each row execute function better_supabase.set_updated_at('updated_at');
-- Deleting an endpoint (or its tenant or subject) deletes its Vault secret.
create or replace function "better_supabase"."drop_incoming_webhook_secret"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from vault.secrets vs where vs.id in (old."secret_id", old."previous_secret_id");
  return null;
end;
$$;
revoke execute on function "better_supabase"."drop_incoming_webhook_secret"() from public, anon, authenticated;
drop trigger if exists "bsb_incoming_webhook_vault" on "better_supabase"."incoming_webhooks";
create trigger "bsb_incoming_webhook_vault" after delete on "better_supabase"."incoming_webhooks"
  for each row when (old."secret_id" is not null or old."previous_secret_id" is not null) execute function "better_supabase"."drop_incoming_webhook_secret"();
alter table "better_supabase"."incoming_webhooks" enable row level security;
revoke all on "better_supabase"."incoming_webhooks" from anon, authenticated;
-- The secret stays with the service: members read every other column.
grant select (id, tenant, name, verify, signature_header, enabled, max_body_bytes, receive_count, last_received_at, last_status, metadata, subject_type, subject_id, created_by, created_at, updated_at) on "better_supabase"."incoming_webhooks" to authenticated;
grant all on "better_supabase"."incoming_webhooks" to service_role;

create or replace function "better_supabase"."incoming_webhook_tenant_ids"()
returns setof uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return query select better_supabase.tenant_ids_with('webhooks.read');
end;
$$;
revoke execute on function "better_supabase"."incoming_webhook_tenant_ids"() from public, anon;
grant execute on function "better_supabase"."incoming_webhook_tenant_ids"() to authenticated, service_role;
-- Whether the caller may read an endpoint's subject: its row is visible to
-- them (the subject table's own policies apply) and they hold its permission.
create or replace function "better_supabase"."incoming_webhook_subject_readable"(subject_type text, subject_id text, tenant uuid)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select subject_type is null or true
$$;
revoke execute on function "better_supabase"."incoming_webhook_subject_readable"(text, text, uuid) from public, anon;
grant execute on function "better_supabase"."incoming_webhook_subject_readable"(text, text, uuid) to authenticated, service_role;

drop policy if exists bsb_incoming_webhooks_read on "better_supabase"."incoming_webhooks";
create policy bsb_incoming_webhooks_read on "better_supabase"."incoming_webhooks" for select to authenticated
  using (
    tenant in (select "better_supabase"."incoming_webhook_tenant_ids"())
    and "better_supabase"."incoming_webhook_subject_readable"(subject_type, subject_id, tenant)
  );

-- A tenant's endpoints, or one subject's, without secrets; runs as the caller.
create or replace function "better_supabase"."list_incoming_webhooks"(tenant uuid, subject_type text default null, subject_id text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', e."id",
    'tenant', e."tenant",
    'name', e."name",
    'verify', e."verify",
    'signature_header', e."signature_header",
    'enabled', e."enabled",
    'max_body_bytes', e."max_body_bytes",
    'receive_count', e."receive_count",
    'last_received_at', e."last_received_at",
    'last_status', e."last_status",
    'metadata', e."metadata",
    'subject_type', e."subject_type",
    'subject_id', e."subject_id",
    'created_by', e."created_by",
    'created_at', e."created_at"
  ) order by e."created_at"), '[]'::jsonb)
  from "better_supabase"."incoming_webhooks" e
  where e."tenant" = list_incoming_webhooks.tenant
    and (list_incoming_webhooks.subject_type is null or e."subject_type" = list_incoming_webhooks.subject_type)
    and (list_incoming_webhooks.subject_id is null or e."subject_id" = list_incoming_webhooks.subject_id)
$$;
revoke execute on function "better_supabase"."list_incoming_webhooks"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."list_incoming_webhooks"(uuid, text, text) to authenticated, service_role;

drop function if exists "better_supabase"."create_incoming_webhook"(uuid, text, text, jsonb, text);
-- Creates an endpoint and returns it with its token (and the signing secret
-- for standard-webhooks and hmac-sha256), shown once.
create or replace function "better_supabase"."create_incoming_webhook"(
  tenant uuid,
  name text,
  verify text default 'none',
  metadata jsonb default '{}',
  signature_header text default null,
  subject_type text default null,
  subject_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid := gen_random_uuid();
  token text := encode(extensions.gen_random_bytes(24), 'hex');
  secret text := case verify
    when 'standard-webhooks' then 'whsec_' || encode(extensions.gen_random_bytes(32), 'base64')
    when 'hmac-sha256' then encode(extensions.gen_random_bytes(32), 'hex')
    when 'shared-secret' then encode(extensions.gen_random_bytes(32), 'hex')
  end;
  created "better_supabase"."incoming_webhooks";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), tenant, 'webhooks.manage'), false)) then
    raise exception 'Not allowed to manage incoming webhooks' using errcode = '42501', hint = 'WEBHOOK_IN_FORBIDDEN';
  end if;
  if verify not in ('none', 'standard-webhooks', 'hmac-sha256', 'shared-secret') then
    raise exception 'Unknown verification mode' using errcode = '22023', hint = 'WEBHOOK_IN_VERIFY_UNKNOWN';
  end if;
  if (subject_type is null) <> (subject_id is null) then
    raise exception 'Pass subject_type and subject_id together' using errcode = '22023', hint = 'WEBHOOK_IN_SUBJECT_INVALID';
  end if;
  if subject_type is not null and not (true) then
    raise exception 'No such subject in this tenant' using errcode = '22023', hint = 'WEBHOOK_IN_SUBJECT_INVALID';
  end if;
  insert into "better_supabase"."incoming_webhooks" ("id", "tenant", "name", "token_hash", "verify", "secret", "secret_id", "signature_header", "metadata", "subject_type", "subject_id", "created_by")
  values (v_id,
    tenant,
    name,
    encode(extensions.digest(token, 'sha256'), 'hex'),
    verify,
    null,
    case when secret is null then null else vault.create_secret(secret, 'webhook-in:' || v_id::text || ':' || gen_random_uuid()::text, 'better-supabase incoming webhook secret') end,
    case verify
      when 'hmac-sha256' then coalesce(signature_header, null, 'x-signature')
      when 'shared-secret' then coalesce(signature_header, null, 'x-webhook-secret')
    end,
    coalesce(metadata, '{}'),
    subject_type,
    subject_id,
    auth.uid())
  returning * into created;
  perform "better_supabase".emit_event('incoming_webhook.created', jsonb_build_object('organizationId', created."tenant"::text, 'endpointId', created."id", 'name', created."name"), 'organizations/' || created."tenant"::text || '/incoming-webhooks/' || created."id"::text, (created."tenant")::text, null, 'better-supabase/webhooks-in');
  perform better_supabase.audit_event(
    event_type => 'incoming_webhook.created',
    category => 'integration',
    target_type => 'incoming_webhook',
    record_id => created."id"::text,
    tenant => (created."tenant")::uuid,
    metadata => jsonb_build_object('organizationId', created."tenant"::text, 'endpointId', created."id", 'name', created."name")
  );
  return jsonb_build_object('id', created."id", 'tenant', created."tenant", 'name', created."name",
    'verify', created."verify", 'token', token, 'secret', secret, 'signatureHeader', created."signature_header",
    'subjectType', created."subject_type", 'subjectId', created."subject_id");
end;
$$;

-- A new token (the old URL stops working); with rotate_secret, a new secret too.
create or replace function "better_supabase"."rotate_incoming_webhook"(endpoint uuid, rotate_secret boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  token text := encode(extensions.gen_random_bytes(24), 'hex');
  v_secret text;
  updated "better_supabase"."incoming_webhooks";
  previous "better_supabase"."incoming_webhooks";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into previous from "better_supabase"."incoming_webhooks" e where e."id" = endpoint for update;
  if previous."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), previous."tenant", 'webhooks.manage'), false)) then
    raise exception 'No incoming webhook %', endpoint using errcode = 'P0002', hint = 'WEBHOOK_IN_NOT_FOUND';
  end if;
  if rotate_secret then
    v_secret := case previous."verify"
    when 'standard-webhooks' then 'whsec_' || encode(extensions.gen_random_bytes(32), 'base64')
    when 'hmac-sha256' then encode(extensions.gen_random_bytes(32), 'hex')
    when 'shared-secret' then encode(extensions.gen_random_bytes(32), 'hex')
  end;
  end if;
  update "better_supabase"."incoming_webhooks" e set "token_hash" = encode(extensions.digest(token, 'sha256'), 'hex'),
    "secret" = case when rotate_secret then null else e."secret" end,
    "secret_id" = case when rotate_secret then case when v_secret is null then null else vault.create_secret(v_secret, 'webhook-in:' || e."id"::text || ':' || gen_random_uuid()::text, 'better-supabase incoming webhook secret') end else e."secret_id" end,
    "previous_secret" = case when rotate_secret then null else e."previous_secret" end,
    "previous_secret_id" = case when rotate_secret then null else e."previous_secret_id" end,
    "previous_secret_expires_at" = case when rotate_secret then null else e."previous_secret_expires_at" end
  where e."id" = endpoint
  returning * into updated;
  if rotate_secret then
    delete from vault.secrets vs where vs.id in (previous."secret_id", previous."previous_secret_id");
  end if;
  perform "better_supabase".emit_event('incoming_webhook.token_rotated', jsonb_build_object('organizationId', updated."tenant"::text, 'endpointId', updated."id", 'secretRotated', rotate_secret), 'organizations/' || updated."tenant"::text || '/incoming-webhooks/' || updated."id"::text, (updated."tenant")::text, null, 'better-supabase/webhooks-in');
  perform better_supabase.audit_event(
    event_type => 'incoming_webhook.token_rotated',
    category => 'security',
    target_type => 'incoming_webhook',
    record_id => updated."id"::text,
    tenant => (updated."tenant")::uuid,
    metadata => jsonb_build_object('organizationId', updated."tenant"::text, 'endpointId', updated."id", 'secretRotated', rotate_secret)
  );
  return jsonb_build_object('id', updated."id", 'token', token, 'secret', v_secret);
end;
$$;

create or replace function "better_supabase"."rotate_incoming_webhook_secret"(endpoint uuid, grace interval default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  previous "better_supabase"."incoming_webhooks";
  updated "better_supabase"."incoming_webhooks";
  v_secret text;
  v_keep boolean := coalesce(grace > interval '0', false);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into previous from "better_supabase"."incoming_webhooks" e where e."id" = endpoint for update;
  if previous."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), previous."tenant", 'webhooks.manage'), false)) then
    raise exception 'No incoming webhook %', endpoint using errcode = 'P0002', hint = 'WEBHOOK_IN_NOT_FOUND';
  end if;
  v_secret := case previous."verify"
    when 'standard-webhooks' then 'whsec_' || encode(extensions.gen_random_bytes(32), 'base64')
    when 'hmac-sha256' then encode(extensions.gen_random_bytes(32), 'hex')
    when 'shared-secret' then encode(extensions.gen_random_bytes(32), 'hex')
  end;
  if v_secret is null then
    raise exception 'This endpoint verifies no secret' using errcode = '22023', hint = 'WEBHOOK_IN_NO_SECRET';
  end if;
  update "better_supabase"."incoming_webhooks" e set
    "secret" = null,
    "secret_id" = case when v_secret is null then null else vault.create_secret(v_secret, 'webhook-in:' || e."id"::text || ':' || gen_random_uuid()::text, 'better-supabase incoming webhook secret') end,
    "previous_secret" = case when v_keep then e."secret" end,
    "previous_secret_id" = case when v_keep then e."secret_id" end,
    "previous_secret_expires_at" = case when v_keep then now() + grace end
  where e."id" = endpoint
  returning * into updated;
  delete from vault.secrets vs
  where vs.id = previous."previous_secret_id" or (not v_keep and vs.id = previous."secret_id");
  perform "better_supabase".emit_event('incoming_webhook.secret_rotated', jsonb_build_object('organizationId', updated."tenant"::text, 'endpointId', updated."id"), 'organizations/' || updated."tenant"::text || '/incoming-webhooks/' || updated."id"::text, (updated."tenant")::text, null, 'better-supabase/webhooks-in');
  perform better_supabase.audit_event(
    event_type => 'incoming_webhook.secret_rotated',
    category => 'security',
    target_type => 'incoming_webhook',
    record_id => updated."id"::text,
    tenant => (updated."tenant")::uuid,
    metadata => jsonb_build_object('organizationId', updated."tenant"::text, 'endpointId', updated."id")
  );
  return jsonb_build_object('id', updated."id", 'secret', v_secret, 'previousSecretExpiresAt', updated."previous_secret_expires_at");
end;
$$;

create or replace function "better_supabase"."update_incoming_webhook"(
  endpoint uuid,
  name text default null,
  metadata jsonb default null,
  verify text default null,
  signature_header text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  previous "better_supabase"."incoming_webhooks";
  updated "better_supabase"."incoming_webhooks";
  v_verify text;
  v_secret text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into previous from "better_supabase"."incoming_webhooks" e where e."id" = endpoint for update;
  if previous."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), previous."tenant", 'webhooks.manage'), false)) then
    raise exception 'No incoming webhook %', endpoint using errcode = 'P0002', hint = 'WEBHOOK_IN_NOT_FOUND';
  end if;
  if name is not null and btrim(name) = '' then
    raise exception 'An endpoint needs a name' using errcode = '22023', hint = 'WEBHOOK_IN_NAME_REQUIRED';
  end if;
  if metadata is not null and jsonb_typeof(metadata) <> 'object' then
    raise exception 'metadata must be a JSON object' using errcode = '22023', hint = 'WEBHOOK_IN_METADATA_INVALID';
  end if;
  v_verify := coalesce(verify, previous."verify");
  if v_verify not in ('none', 'standard-webhooks', 'hmac-sha256', 'shared-secret') then
    raise exception 'Unknown verification mode' using errcode = '22023', hint = 'WEBHOOK_IN_VERIFY_UNKNOWN';
  end if;
  if v_verify <> previous."verify" then
    v_secret := case v_verify
    when 'standard-webhooks' then 'whsec_' || encode(extensions.gen_random_bytes(32), 'base64')
    when 'hmac-sha256' then encode(extensions.gen_random_bytes(32), 'hex')
    when 'shared-secret' then encode(extensions.gen_random_bytes(32), 'hex')
  end;
  end if;
  update "better_supabase"."incoming_webhooks" e set
    "name" = coalesce(update_incoming_webhook.name, e."name"),
    "metadata" = coalesce(update_incoming_webhook.metadata, e."metadata"),
    "verify" = v_verify,
    "secret" = case when v_verify = previous."verify" then e."secret" else null end,
    "secret_id" = case when v_verify = previous."verify" then e."secret_id" else case when v_secret is null then null else vault.create_secret(v_secret, 'webhook-in:' || e."id"::text || ':' || gen_random_uuid()::text, 'better-supabase incoming webhook secret') end end,
    "previous_secret" = case when v_verify = previous."verify" then e."previous_secret" end,
    "previous_secret_id" = case when v_verify = previous."verify" then e."previous_secret_id" end,
    "previous_secret_expires_at" = case when v_verify = previous."verify" then e."previous_secret_expires_at" end,
    "signature_header" = case v_verify
      when 'hmac-sha256' then coalesce(update_incoming_webhook.signature_header, case when v_verify = previous."verify" then e."signature_header" end, 'x-signature')
      when 'shared-secret' then coalesce(update_incoming_webhook.signature_header, case when v_verify = previous."verify" then e."signature_header" end, 'x-webhook-secret')
    end
  where e."id" = endpoint
  returning * into updated;
  if v_verify <> previous."verify" then
    delete from vault.secrets vs where vs.id in (previous."secret_id", previous."previous_secret_id");
  end if;
  perform "better_supabase".emit_event('incoming_webhook.updated', jsonb_build_object('organizationId', updated."tenant"::text, 'endpointId', updated."id", 'name', updated."name", 'verify', updated."verify"), 'organizations/' || updated."tenant"::text || '/incoming-webhooks/' || updated."id"::text, (updated."tenant")::text, null, 'better-supabase/webhooks-in');
  perform better_supabase.audit_event(
    event_type => 'incoming_webhook.updated',
    category => 'integration',
    target_type => 'incoming_webhook',
    record_id => updated."id"::text,
    tenant => (updated."tenant")::uuid,
    metadata => jsonb_build_object('organizationId', updated."tenant"::text, 'endpointId', updated."id", 'name', updated."name", 'verify', updated."verify")
  );
  return jsonb_build_object('id', updated."id", 'tenant', updated."tenant", 'name', updated."name",
    'verify', updated."verify", 'secret', v_secret, 'signatureHeader', updated."signature_header",
    'metadata', updated."metadata");
end;
$$;

create or replace function "better_supabase"."set_incoming_webhook_enabled"(endpoint uuid, enabled boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select e."tenant" into tenant from "better_supabase"."incoming_webhooks" e where e."id" = endpoint;
  if tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), tenant, 'webhooks.manage'), false)) then
    return false;
  end if;
  update "better_supabase"."incoming_webhooks" e set "enabled" = set_incoming_webhook_enabled.enabled where e."id" = endpoint;
  perform "better_supabase".emit_event('incoming_webhook.enabled_set', jsonb_build_object('organizationId', tenant::text, 'endpointId', endpoint, 'enabled', set_incoming_webhook_enabled.enabled), 'organizations/' || tenant::text || '/incoming-webhooks/' || endpoint::text, (tenant)::text, null, 'better-supabase/webhooks-in');
  perform better_supabase.audit_event(
    event_type => 'incoming_webhook.enabled_set',
    category => 'integration',
    target_type => 'incoming_webhook',
    record_id => endpoint::text,
    tenant => (tenant)::uuid,
    metadata => jsonb_build_object('organizationId', tenant::text, 'endpointId', endpoint, 'enabled', set_incoming_webhook_enabled.enabled)
  );
  return true;
end;
$$;

create or replace function "better_supabase"."delete_incoming_webhook"(endpoint uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select e."tenant" into tenant from "better_supabase"."incoming_webhooks" e where e."id" = endpoint;
  if tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), tenant, 'webhooks.manage'), false)) then
    return false;
  end if;
  delete from "better_supabase"."incoming_webhooks" e where e."id" = endpoint;
  perform "better_supabase".emit_event('incoming_webhook.deleted', jsonb_build_object('organizationId', tenant::text, 'endpointId', endpoint), 'organizations/' || tenant::text || '/incoming-webhooks/' || endpoint::text, (tenant)::text, null, 'better-supabase/webhooks-in');
  perform better_supabase.audit_event(
    event_type => 'incoming_webhook.deleted',
    category => 'integration',
    target_type => 'incoming_webhook',
    record_id => endpoint::text,
    tenant => (tenant)::uuid,
    metadata => jsonb_build_object('organizationId', tenant::text, 'endpointId', endpoint)
  );
  return true;
end;
$$;

-- The endpoint behind a token, with its secret and metadata, for the
-- receiving route.
drop function if exists "better_supabase"."incoming_webhook_by_token"(text);
create or replace function "better_supabase"."incoming_webhook_by_token"(token text)
returns table (id uuid, tenant text, enabled boolean, verify text, secret text, signature_header text, max_body_bytes integer, previous_secret text, metadata jsonb)
language sql
stable
security definer
set search_path = ''
as $$
  select e."id", e."tenant"::text, e."enabled", e."verify", coalesce(ds.decrypted_secret, e."secret"), e."signature_header", e."max_body_bytes",
    case when e."previous_secret_expires_at" > now() then coalesce(dp.decrypted_secret, e."previous_secret") end, e."metadata"
  from "better_supabase"."incoming_webhooks" e
  left join vault.decrypted_secrets ds on ds.id = e."secret_id"
  left join vault.decrypted_secrets dp on dp.id = e."previous_secret_id"
  where e."token_hash" = encode(extensions.digest(incoming_webhook_by_token.token, 'sha256'), 'hex')
$$;

-- Counts a delivery and keeps its HTTP status.
create or replace function "better_supabase"."record_incoming_webhook"(endpoint uuid, status integer)
returns void
language sql
security definer
set search_path = ''
as $$
  update "better_supabase"."incoming_webhooks" e
  set "receive_count" = e."receive_count" + 1, "last_received_at" = now(), "last_status" = record_incoming_webhook.status
  where e."id" = endpoint
$$;

revoke execute on function "better_supabase"."create_incoming_webhook"(uuid, text, text, jsonb, text, text, text) from public, anon;
grant execute on function "better_supabase"."create_incoming_webhook"(uuid, text, text, jsonb, text, text, text) to authenticated, service_role;
revoke execute on function "better_supabase"."rotate_incoming_webhook"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."rotate_incoming_webhook"(uuid, boolean) to authenticated, service_role;
revoke execute on function "better_supabase"."rotate_incoming_webhook_secret"(uuid, interval) from public, anon;
grant execute on function "better_supabase"."rotate_incoming_webhook_secret"(uuid, interval) to authenticated, service_role;
revoke execute on function "better_supabase"."update_incoming_webhook"(uuid, text, jsonb, text, text) from public, anon;
grant execute on function "better_supabase"."update_incoming_webhook"(uuid, text, jsonb, text, text) to authenticated, service_role;
revoke execute on function "better_supabase"."set_incoming_webhook_enabled"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."set_incoming_webhook_enabled"(uuid, boolean) to authenticated, service_role;
revoke execute on function "better_supabase"."delete_incoming_webhook"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_incoming_webhook"(uuid) to authenticated, service_role;
revoke execute on function "better_supabase"."incoming_webhook_by_token"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."incoming_webhook_by_token"(text) to service_role;
revoke execute on function "better_supabase"."record_incoming_webhook"(uuid, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."record_incoming_webhook"(uuid, integer) to service_role;

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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_27_webhooks_in.sql
-- better-supabase module: webhooks-in
-- @bs-module-data webhooks-in
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('webhooks-in', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_27_webhooks_in.sql
-- better-supabase module: webhooks-in
-- @bs-module webhooks-in@4 managed
-- Per-tenant trigger URLs with a hashed token, optional Standard Webhooks or HMAC verification, a body size limit, receive counters and the last status; deliveries go to the webhook inbox with the endpoint's tenant.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
-- Trigger URLs a tenant hands to another system: /hooks/<token> stores each
-- delivery in the webhook inbox (source webhook-in), with the endpoint's
-- tenant. Only the token's hash is kept, and the signing secret is a Vault
-- secret (secret_id) unless options.secretStorage is "column".
create table if not exists "app_private"."incoming_webhooks" (
  id uuid primary key default gen_random_uuid(),
  tenant uuid not null,
  name text not null,
  token_hash text not null unique,
  verify text not null default 'none' check (verify in ('none', 'standard-webhooks', 'hmac-sha256', 'shared-secret')),
  secret text,
  secret_id uuid,
  previous_secret text,
  previous_secret_id uuid,
  previous_secret_expires_at timestamptz,
  signature_header text,
  enabled boolean not null default true,
  max_body_bytes integer not null default 1048576 check (max_body_bytes > 0),
  receive_count bigint not null default 0,
  last_received_at timestamptz,
  last_status integer,
  metadata jsonb not null default '{}',
  subject_type text check (subject_type ~ '^[a-z][a-z0-9_]{0,62}$'),
  subject_id text check (length(subject_id) between 1 and 200),
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table "app_private"."incoming_webhooks" add column if not exists subject_type text check (subject_type ~ '^[a-z][a-z0-9_]{0,62}$');
alter table "app_private"."incoming_webhooks" add column if not exists subject_id text check (length(subject_id) between 1 and 200);
alter table "app_private"."incoming_webhooks" add column if not exists secret_id uuid;
alter table "app_private"."incoming_webhooks" drop constraint if exists incoming_webhooks_verify_check;
alter table "app_private"."incoming_webhooks" add constraint incoming_webhooks_verify_check check (verify in ('none', 'standard-webhooks', 'hmac-sha256', 'shared-secret'));
alter table "app_private"."incoming_webhooks" add column if not exists previous_secret text;
alter table "app_private"."incoming_webhooks" add column if not exists previous_secret_id uuid;
alter table "app_private"."incoming_webhooks" add column if not exists previous_secret_expires_at timestamptz;
create index if not exists incoming_webhooks_tenant_idx on "app_private"."incoming_webhooks" (tenant);
create index if not exists incoming_webhooks_subject_idx on "app_private"."incoming_webhooks" (tenant, subject_type, subject_id);
create index if not exists incoming_webhooks_created_by_idx on "app_private"."incoming_webhooks" (created_by) where created_by is not null;
alter table "app_private"."incoming_webhooks" add column if not exists updated_at timestamptz not null default now();
drop trigger if exists bsb_updated_at on "app_private"."incoming_webhooks";
create trigger bsb_updated_at before update on "app_private"."incoming_webhooks"
  for each row execute function better_supabase.set_updated_at('updated_at');
-- Deleting an endpoint (or its tenant or subject) deletes its Vault secret.
create or replace function "app_private"."drop_incoming_webhook_secret"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from vault.secrets vs where vs.id in (old."secret_id", old."previous_secret_id");
  return null;
end;
$$;
revoke execute on function "app_private"."drop_incoming_webhook_secret"() from public, anon, authenticated;
drop trigger if exists "bsb_incoming_webhook_vault" on "app_private"."incoming_webhooks";
create trigger "bsb_incoming_webhook_vault" after delete on "app_private"."incoming_webhooks"
  for each row when (old."secret_id" is not null or old."previous_secret_id" is not null) execute function "app_private"."drop_incoming_webhook_secret"();
alter table "app_private"."incoming_webhooks" enable row level security;
revoke all on "app_private"."incoming_webhooks" from anon, authenticated;
-- The secret stays with the service: members read every other column.
grant select (id, tenant, name, verify, signature_header, enabled, max_body_bytes, receive_count, last_received_at, last_status, metadata, subject_type, subject_id, created_by, created_at, updated_at) on "app_private"."incoming_webhooks" to authenticated;
grant all on "app_private"."incoming_webhooks" to service_role;

create or replace function "app_private"."incoming_webhook_tenant_ids"()
returns setof uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return query select better_supabase.tenant_ids_with('webhooks.read');
end;
$$;
revoke execute on function "app_private"."incoming_webhook_tenant_ids"() from public, anon;
grant execute on function "app_private"."incoming_webhook_tenant_ids"() to authenticated, service_role;
-- Whether the caller may read an endpoint's subject: its row is visible to
-- them (the subject table's own policies apply) and they hold its permission.
create or replace function "app_private"."incoming_webhook_subject_readable"(subject_type text, subject_id text, tenant uuid)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select subject_type is null or true
$$;
revoke execute on function "app_private"."incoming_webhook_subject_readable"(text, text, uuid) from public, anon;
grant execute on function "app_private"."incoming_webhook_subject_readable"(text, text, uuid) to authenticated, service_role;

drop policy if exists bsb_incoming_webhooks_read on "app_private"."incoming_webhooks";
create policy bsb_incoming_webhooks_read on "app_private"."incoming_webhooks" for select to authenticated
  using (
    tenant in (select "app_private"."incoming_webhook_tenant_ids"())
    and "app_private"."incoming_webhook_subject_readable"(subject_type, subject_id, tenant)
  );

-- A tenant's endpoints, or one subject's, without secrets; runs as the caller.
create or replace function "app_private"."list_incoming_webhooks"(tenant uuid, subject_type text default null, subject_id text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', e."id",
    'tenant', e."tenant",
    'name', e."name",
    'verify', e."verify",
    'signature_header', e."signature_header",
    'enabled', e."enabled",
    'max_body_bytes', e."max_body_bytes",
    'receive_count', e."receive_count",
    'last_received_at', e."last_received_at",
    'last_status', e."last_status",
    'metadata', e."metadata",
    'subject_type', e."subject_type",
    'subject_id', e."subject_id",
    'created_by', e."created_by",
    'created_at', e."created_at"
  ) order by e."created_at"), '[]'::jsonb)
  from "app_private"."incoming_webhooks" e
  where e."tenant" = list_incoming_webhooks.tenant
    and (list_incoming_webhooks.subject_type is null or e."subject_type" = list_incoming_webhooks.subject_type)
    and (list_incoming_webhooks.subject_id is null or e."subject_id" = list_incoming_webhooks.subject_id)
$$;
revoke execute on function "app_private"."list_incoming_webhooks"(uuid, text, text) from public, anon;
grant execute on function "app_private"."list_incoming_webhooks"(uuid, text, text) to authenticated, service_role;

drop function if exists "app_private"."create_incoming_webhook"(uuid, text, text, jsonb, text);
-- Creates an endpoint and returns it with its token (and the signing secret
-- for standard-webhooks and hmac-sha256), shown once.
create or replace function "app_private"."create_incoming_webhook"(
  tenant uuid,
  name text,
  verify text default 'none',
  metadata jsonb default '{}',
  signature_header text default null,
  subject_type text default null,
  subject_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid := gen_random_uuid();
  token text := encode(extensions.gen_random_bytes(24), 'hex');
  secret text := case verify
    when 'standard-webhooks' then 'whsec_' || encode(extensions.gen_random_bytes(32), 'base64')
    when 'hmac-sha256' then encode(extensions.gen_random_bytes(32), 'hex')
    when 'shared-secret' then encode(extensions.gen_random_bytes(32), 'hex')
  end;
  created "app_private"."incoming_webhooks";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), tenant, 'webhooks.manage'), false)) then
    raise exception 'Not allowed to manage incoming webhooks' using errcode = '42501', hint = 'WEBHOOK_IN_FORBIDDEN';
  end if;
  if verify not in ('none', 'standard-webhooks', 'hmac-sha256', 'shared-secret') then
    raise exception 'Unknown verification mode' using errcode = '22023', hint = 'WEBHOOK_IN_VERIFY_UNKNOWN';
  end if;
  if (subject_type is null) <> (subject_id is null) then
    raise exception 'Pass subject_type and subject_id together' using errcode = '22023', hint = 'WEBHOOK_IN_SUBJECT_INVALID';
  end if;
  if subject_type is not null and not (true) then
    raise exception 'No such subject in this tenant' using errcode = '22023', hint = 'WEBHOOK_IN_SUBJECT_INVALID';
  end if;
  insert into "app_private"."incoming_webhooks" ("id", "tenant", "name", "token_hash", "verify", "secret", "secret_id", "signature_header", "metadata", "subject_type", "subject_id", "created_by")
  values (v_id,
    tenant,
    name,
    encode(extensions.digest(token, 'sha256'), 'hex'),
    verify,
    null,
    case when secret is null then null else vault.create_secret(secret, 'webhook-in:' || v_id::text || ':' || gen_random_uuid()::text, 'better-supabase incoming webhook secret') end,
    case verify
      when 'hmac-sha256' then coalesce(signature_header, null, 'x-signature')
      when 'shared-secret' then coalesce(signature_header, null, 'x-webhook-secret')
    end,
    coalesce(metadata, '{}'),
    subject_type,
    subject_id,
    auth.uid())
  returning * into created;
  null;
  return jsonb_build_object('id', created."id", 'tenant', created."tenant", 'name', created."name",
    'verify', created."verify", 'token', token, 'secret', secret, 'signatureHeader', created."signature_header",
    'subjectType', created."subject_type", 'subjectId', created."subject_id");
end;
$$;

-- A new token (the old URL stops working); with rotate_secret, a new secret too.
create or replace function "app_private"."rotate_incoming_webhook"(endpoint uuid, rotate_secret boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  token text := encode(extensions.gen_random_bytes(24), 'hex');
  v_secret text;
  updated "app_private"."incoming_webhooks";
  previous "app_private"."incoming_webhooks";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into previous from "app_private"."incoming_webhooks" e where e."id" = endpoint for update;
  if previous."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), previous."tenant", 'webhooks.manage'), false)) then
    raise exception 'No incoming webhook %', endpoint using errcode = 'P0002', hint = 'WEBHOOK_IN_NOT_FOUND';
  end if;
  if rotate_secret then
    v_secret := case previous."verify"
    when 'standard-webhooks' then 'whsec_' || encode(extensions.gen_random_bytes(32), 'base64')
    when 'hmac-sha256' then encode(extensions.gen_random_bytes(32), 'hex')
    when 'shared-secret' then encode(extensions.gen_random_bytes(32), 'hex')
  end;
  end if;
  update "app_private"."incoming_webhooks" e set "token_hash" = encode(extensions.digest(token, 'sha256'), 'hex'),
    "secret" = case when rotate_secret then null else e."secret" end,
    "secret_id" = case when rotate_secret then case when v_secret is null then null else vault.create_secret(v_secret, 'webhook-in:' || e."id"::text || ':' || gen_random_uuid()::text, 'better-supabase incoming webhook secret') end else e."secret_id" end,
    "previous_secret" = case when rotate_secret then null else e."previous_secret" end,
    "previous_secret_id" = case when rotate_secret then null else e."previous_secret_id" end,
    "previous_secret_expires_at" = case when rotate_secret then null else e."previous_secret_expires_at" end
  where e."id" = endpoint
  returning * into updated;
  if rotate_secret then
    delete from vault.secrets vs where vs.id in (previous."secret_id", previous."previous_secret_id");
  end if;
  null;
  return jsonb_build_object('id', updated."id", 'token', token, 'secret', v_secret);
end;
$$;

create or replace function "app_private"."rotate_incoming_webhook_secret"(endpoint uuid, grace interval default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  previous "app_private"."incoming_webhooks";
  updated "app_private"."incoming_webhooks";
  v_secret text;
  v_keep boolean := coalesce(grace > interval '0', false);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into previous from "app_private"."incoming_webhooks" e where e."id" = endpoint for update;
  if previous."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), previous."tenant", 'webhooks.manage'), false)) then
    raise exception 'No incoming webhook %', endpoint using errcode = 'P0002', hint = 'WEBHOOK_IN_NOT_FOUND';
  end if;
  v_secret := case previous."verify"
    when 'standard-webhooks' then 'whsec_' || encode(extensions.gen_random_bytes(32), 'base64')
    when 'hmac-sha256' then encode(extensions.gen_random_bytes(32), 'hex')
    when 'shared-secret' then encode(extensions.gen_random_bytes(32), 'hex')
  end;
  if v_secret is null then
    raise exception 'This endpoint verifies no secret' using errcode = '22023', hint = 'WEBHOOK_IN_NO_SECRET';
  end if;
  update "app_private"."incoming_webhooks" e set
    "secret" = null,
    "secret_id" = case when v_secret is null then null else vault.create_secret(v_secret, 'webhook-in:' || e."id"::text || ':' || gen_random_uuid()::text, 'better-supabase incoming webhook secret') end,
    "previous_secret" = case when v_keep then e."secret" end,
    "previous_secret_id" = case when v_keep then e."secret_id" end,
    "previous_secret_expires_at" = case when v_keep then now() + grace end
  where e."id" = endpoint
  returning * into updated;
  delete from vault.secrets vs
  where vs.id = previous."previous_secret_id" or (not v_keep and vs.id = previous."secret_id");
  null;
  return jsonb_build_object('id', updated."id", 'secret', v_secret, 'previousSecretExpiresAt', updated."previous_secret_expires_at");
end;
$$;

create or replace function "app_private"."update_incoming_webhook"(
  endpoint uuid,
  name text default null,
  metadata jsonb default null,
  verify text default null,
  signature_header text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  previous "app_private"."incoming_webhooks";
  updated "app_private"."incoming_webhooks";
  v_verify text;
  v_secret text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into previous from "app_private"."incoming_webhooks" e where e."id" = endpoint for update;
  if previous."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), previous."tenant", 'webhooks.manage'), false)) then
    raise exception 'No incoming webhook %', endpoint using errcode = 'P0002', hint = 'WEBHOOK_IN_NOT_FOUND';
  end if;
  if name is not null and btrim(name) = '' then
    raise exception 'An endpoint needs a name' using errcode = '22023', hint = 'WEBHOOK_IN_NAME_REQUIRED';
  end if;
  if metadata is not null and jsonb_typeof(metadata) <> 'object' then
    raise exception 'metadata must be a JSON object' using errcode = '22023', hint = 'WEBHOOK_IN_METADATA_INVALID';
  end if;
  v_verify := coalesce(verify, previous."verify");
  if v_verify not in ('none', 'standard-webhooks', 'hmac-sha256', 'shared-secret') then
    raise exception 'Unknown verification mode' using errcode = '22023', hint = 'WEBHOOK_IN_VERIFY_UNKNOWN';
  end if;
  if v_verify <> previous."verify" then
    v_secret := case v_verify
    when 'standard-webhooks' then 'whsec_' || encode(extensions.gen_random_bytes(32), 'base64')
    when 'hmac-sha256' then encode(extensions.gen_random_bytes(32), 'hex')
    when 'shared-secret' then encode(extensions.gen_random_bytes(32), 'hex')
  end;
  end if;
  update "app_private"."incoming_webhooks" e set
    "name" = coalesce(update_incoming_webhook.name, e."name"),
    "metadata" = coalesce(update_incoming_webhook.metadata, e."metadata"),
    "verify" = v_verify,
    "secret" = case when v_verify = previous."verify" then e."secret" else null end,
    "secret_id" = case when v_verify = previous."verify" then e."secret_id" else case when v_secret is null then null else vault.create_secret(v_secret, 'webhook-in:' || e."id"::text || ':' || gen_random_uuid()::text, 'better-supabase incoming webhook secret') end end,
    "previous_secret" = case when v_verify = previous."verify" then e."previous_secret" end,
    "previous_secret_id" = case when v_verify = previous."verify" then e."previous_secret_id" end,
    "previous_secret_expires_at" = case when v_verify = previous."verify" then e."previous_secret_expires_at" end,
    "signature_header" = case v_verify
      when 'hmac-sha256' then coalesce(update_incoming_webhook.signature_header, case when v_verify = previous."verify" then e."signature_header" end, 'x-signature')
      when 'shared-secret' then coalesce(update_incoming_webhook.signature_header, case when v_verify = previous."verify" then e."signature_header" end, 'x-webhook-secret')
    end
  where e."id" = endpoint
  returning * into updated;
  if v_verify <> previous."verify" then
    delete from vault.secrets vs where vs.id in (previous."secret_id", previous."previous_secret_id");
  end if;
  null;
  return jsonb_build_object('id', updated."id", 'tenant', updated."tenant", 'name', updated."name",
    'verify', updated."verify", 'secret', v_secret, 'signatureHeader', updated."signature_header",
    'metadata', updated."metadata");
end;
$$;

create or replace function "app_private"."set_incoming_webhook_enabled"(endpoint uuid, enabled boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select e."tenant" into tenant from "app_private"."incoming_webhooks" e where e."id" = endpoint;
  if tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), tenant, 'webhooks.manage'), false)) then
    return false;
  end if;
  update "app_private"."incoming_webhooks" e set "enabled" = set_incoming_webhook_enabled.enabled where e."id" = endpoint;
  null;
  return true;
end;
$$;

create or replace function "app_private"."delete_incoming_webhook"(endpoint uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select e."tenant" into tenant from "app_private"."incoming_webhooks" e where e."id" = endpoint;
  if tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), tenant, 'webhooks.manage'), false)) then
    return false;
  end if;
  delete from "app_private"."incoming_webhooks" e where e."id" = endpoint;
  null;
  return true;
end;
$$;

-- The endpoint behind a token, with its secret and metadata, for the
-- receiving route.
drop function if exists "app_private"."incoming_webhook_by_token"(text);
create or replace function "app_private"."incoming_webhook_by_token"(token text)
returns table (id uuid, tenant text, enabled boolean, verify text, secret text, signature_header text, max_body_bytes integer, previous_secret text, metadata jsonb)
language sql
stable
security definer
set search_path = ''
as $$
  select e."id", e."tenant"::text, e."enabled", e."verify", coalesce(ds.decrypted_secret, e."secret"), e."signature_header", e."max_body_bytes",
    case when e."previous_secret_expires_at" > now() then coalesce(dp.decrypted_secret, e."previous_secret") end, e."metadata"
  from "app_private"."incoming_webhooks" e
  left join vault.decrypted_secrets ds on ds.id = e."secret_id"
  left join vault.decrypted_secrets dp on dp.id = e."previous_secret_id"
  where e."token_hash" = encode(extensions.digest(incoming_webhook_by_token.token, 'sha256'), 'hex')
$$;

-- Counts a delivery and keeps its HTTP status.
create or replace function "app_private"."record_incoming_webhook"(endpoint uuid, status integer)
returns void
language sql
security definer
set search_path = ''
as $$
  update "app_private"."incoming_webhooks" e
  set "receive_count" = e."receive_count" + 1, "last_received_at" = now(), "last_status" = record_incoming_webhook.status
  where e."id" = endpoint
$$;

revoke execute on function "app_private"."create_incoming_webhook"(uuid, text, text, jsonb, text, text, text) from public, anon;
grant execute on function "app_private"."create_incoming_webhook"(uuid, text, text, jsonb, text, text, text) to authenticated, service_role;
revoke execute on function "app_private"."rotate_incoming_webhook"(uuid, boolean) from public, anon;
grant execute on function "app_private"."rotate_incoming_webhook"(uuid, boolean) to authenticated, service_role;
revoke execute on function "app_private"."rotate_incoming_webhook_secret"(uuid, interval) from public, anon;
grant execute on function "app_private"."rotate_incoming_webhook_secret"(uuid, interval) to authenticated, service_role;
revoke execute on function "app_private"."update_incoming_webhook"(uuid, text, jsonb, text, text) from public, anon;
grant execute on function "app_private"."update_incoming_webhook"(uuid, text, jsonb, text, text) to authenticated, service_role;
revoke execute on function "app_private"."set_incoming_webhook_enabled"(uuid, boolean) from public, anon;
grant execute on function "app_private"."set_incoming_webhook_enabled"(uuid, boolean) to authenticated, service_role;
revoke execute on function "app_private"."delete_incoming_webhook"(uuid) from public, anon;
grant execute on function "app_private"."delete_incoming_webhook"(uuid) to authenticated, service_role;
revoke execute on function "app_private"."incoming_webhook_by_token"(text) from public, anon, authenticated;
grant execute on function "app_private"."incoming_webhook_by_token"(text) to service_role;
revoke execute on function "app_private"."record_incoming_webhook"(uuid, integer) from public, anon, authenticated;
grant execute on function "app_private"."record_incoming_webhook"(uuid, integer) to service_role;

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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_27_webhooks_in.sql
-- better-supabase module: webhooks-in
-- @bs-module-data webhooks-in
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('webhooks-in', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_27_webhooks_in.sql
-- better-supabase module: webhooks-in
-- @bs-module webhooks-in@4 managed
-- Per-tenant trigger URLs with a hashed token, optional Standard Webhooks or HMAC verification, a body size limit, receive counters and the last status; deliveries go to the webhook inbox with the endpoint's tenant.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Trigger URLs a tenant hands to another system: /hooks/<token> stores each
-- delivery in the webhook inbox (source webhook-in), with the endpoint's
-- tenant. Only the token's hash is kept, and the signing secret is a Vault
-- secret (secret_id) unless options.secretStorage is "column".
create table if not exists "better_supabase"."incoming_webhooks" (
  id uuid primary key default gen_random_uuid(),
  tenant uuid not null,
  name text not null,
  token_hash text not null unique,
  verify text not null default 'none' check (verify in ('none', 'standard-webhooks', 'hmac-sha256', 'shared-secret')),
  secret text,
  secret_id uuid,
  previous_secret text,
  previous_secret_id uuid,
  previous_secret_expires_at timestamptz,
  signature_header text,
  enabled boolean not null default true,
  max_body_bytes integer not null default 1048576 check (max_body_bytes > 0),
  receive_count bigint not null default 0,
  last_received_at timestamptz,
  last_status integer,
  metadata jsonb not null default '{}',
  subject_type text check (subject_type ~ '^[a-z][a-z0-9_]{0,62}$'),
  subject_id text check (length(subject_id) between 1 and 200),
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table "better_supabase"."incoming_webhooks" add column if not exists subject_type text check (subject_type ~ '^[a-z][a-z0-9_]{0,62}$');
alter table "better_supabase"."incoming_webhooks" add column if not exists subject_id text check (length(subject_id) between 1 and 200);
alter table "better_supabase"."incoming_webhooks" add column if not exists secret_id uuid;
alter table "better_supabase"."incoming_webhooks" drop constraint if exists incoming_webhooks_verify_check;
alter table "better_supabase"."incoming_webhooks" add constraint incoming_webhooks_verify_check check (verify in ('none', 'standard-webhooks', 'hmac-sha256', 'shared-secret'));
alter table "better_supabase"."incoming_webhooks" add column if not exists previous_secret text;
alter table "better_supabase"."incoming_webhooks" add column if not exists previous_secret_id uuid;
alter table "better_supabase"."incoming_webhooks" add column if not exists previous_secret_expires_at timestamptz;
create index if not exists incoming_webhooks_tenant_idx on "better_supabase"."incoming_webhooks" (tenant);
create index if not exists incoming_webhooks_subject_idx on "better_supabase"."incoming_webhooks" (tenant, subject_type, subject_id);
create index if not exists incoming_webhooks_created_by_idx on "better_supabase"."incoming_webhooks" (created_by) where created_by is not null;
alter table "better_supabase"."incoming_webhooks" add column if not exists updated_at timestamptz not null default now();
drop trigger if exists bsb_updated_at on "better_supabase"."incoming_webhooks";
create trigger bsb_updated_at before update on "better_supabase"."incoming_webhooks"
  for each row execute function better_supabase.set_updated_at('updated_at');
-- Deleting an endpoint (or its tenant or subject) deletes its Vault secret.
create or replace function "better_supabase"."drop_incoming_webhook_secret"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from vault.secrets vs where vs.id in (old."secret_id", old."previous_secret_id");
  return null;
end;
$$;
revoke execute on function "better_supabase"."drop_incoming_webhook_secret"() from public, anon, authenticated;
drop trigger if exists "bsb_incoming_webhook_vault" on "better_supabase"."incoming_webhooks";
create trigger "bsb_incoming_webhook_vault" after delete on "better_supabase"."incoming_webhooks"
  for each row when (old."secret_id" is not null or old."previous_secret_id" is not null) execute function "better_supabase"."drop_incoming_webhook_secret"();
alter table "better_supabase"."incoming_webhooks" enable row level security;
revoke all on "better_supabase"."incoming_webhooks" from anon, authenticated;
-- The secret stays with the service: members read every other column.
grant select (id, tenant, name, verify, signature_header, enabled, max_body_bytes, receive_count, last_received_at, last_status, metadata, subject_type, subject_id, created_by, created_at, updated_at) on "better_supabase"."incoming_webhooks" to authenticated;
grant all on "better_supabase"."incoming_webhooks" to service_role;

create or replace function "better_supabase"."incoming_webhook_tenant_ids"()
returns setof uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return query select better_supabase.tenant_ids_with('webhooks.read');
end;
$$;
revoke execute on function "better_supabase"."incoming_webhook_tenant_ids"() from public, anon;
grant execute on function "better_supabase"."incoming_webhook_tenant_ids"() to authenticated, service_role;
-- Whether the caller may read an endpoint's subject: its row is visible to
-- them (the subject table's own policies apply) and they hold its permission.
create or replace function "better_supabase"."incoming_webhook_subject_readable"(subject_type text, subject_id text, tenant uuid)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select subject_type is null or true
$$;
revoke execute on function "better_supabase"."incoming_webhook_subject_readable"(text, text, uuid) from public, anon;
grant execute on function "better_supabase"."incoming_webhook_subject_readable"(text, text, uuid) to authenticated, service_role;

drop policy if exists bsb_incoming_webhooks_read on "better_supabase"."incoming_webhooks";
create policy bsb_incoming_webhooks_read on "better_supabase"."incoming_webhooks" for select to authenticated
  using (
    tenant in (select "better_supabase"."incoming_webhook_tenant_ids"())
    and "better_supabase"."incoming_webhook_subject_readable"(subject_type, subject_id, tenant)
  );

-- A tenant's endpoints, or one subject's, without secrets; runs as the caller.
create or replace function "better_supabase"."list_incoming_webhooks"(tenant uuid, subject_type text default null, subject_id text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', e."id",
    'tenant', e."tenant",
    'name', e."name",
    'verify', e."verify",
    'signature_header', e."signature_header",
    'enabled', e."enabled",
    'max_body_bytes', e."max_body_bytes",
    'receive_count', e."receive_count",
    'last_received_at', e."last_received_at",
    'last_status', e."last_status",
    'metadata', e."metadata",
    'subject_type', e."subject_type",
    'subject_id', e."subject_id",
    'created_by', e."created_by",
    'created_at', e."created_at"
  ) order by e."created_at"), '[]'::jsonb)
  from "better_supabase"."incoming_webhooks" e
  where e."tenant" = list_incoming_webhooks.tenant
    and (list_incoming_webhooks.subject_type is null or e."subject_type" = list_incoming_webhooks.subject_type)
    and (list_incoming_webhooks.subject_id is null or e."subject_id" = list_incoming_webhooks.subject_id)
$$;
revoke execute on function "better_supabase"."list_incoming_webhooks"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."list_incoming_webhooks"(uuid, text, text) to authenticated, service_role;

drop function if exists "better_supabase"."create_incoming_webhook"(uuid, text, text, jsonb, text);
-- Creates an endpoint and returns it with its token (and the signing secret
-- for standard-webhooks and hmac-sha256), shown once.
create or replace function "better_supabase"."create_incoming_webhook"(
  tenant uuid,
  name text,
  verify text default 'none',
  metadata jsonb default '{}',
  signature_header text default null,
  subject_type text default null,
  subject_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid := gen_random_uuid();
  token text := encode(extensions.gen_random_bytes(24), 'hex');
  secret text := case verify
    when 'standard-webhooks' then 'whsec_' || encode(extensions.gen_random_bytes(32), 'base64')
    when 'hmac-sha256' then encode(extensions.gen_random_bytes(32), 'hex')
    when 'shared-secret' then encode(extensions.gen_random_bytes(32), 'hex')
  end;
  created "better_supabase"."incoming_webhooks";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), tenant, 'webhooks.manage'), false)) then
    raise exception 'Not allowed to manage incoming webhooks' using errcode = '42501', hint = 'WEBHOOK_IN_FORBIDDEN';
  end if;
  if verify not in ('none', 'standard-webhooks', 'hmac-sha256', 'shared-secret') then
    raise exception 'Unknown verification mode' using errcode = '22023', hint = 'WEBHOOK_IN_VERIFY_UNKNOWN';
  end if;
  if (subject_type is null) <> (subject_id is null) then
    raise exception 'Pass subject_type and subject_id together' using errcode = '22023', hint = 'WEBHOOK_IN_SUBJECT_INVALID';
  end if;
  if subject_type is not null and not (true) then
    raise exception 'No such subject in this tenant' using errcode = '22023', hint = 'WEBHOOK_IN_SUBJECT_INVALID';
  end if;
  insert into "better_supabase"."incoming_webhooks" ("id", "tenant", "name", "token_hash", "verify", "secret", "secret_id", "signature_header", "metadata", "subject_type", "subject_id", "created_by")
  values (v_id,
    tenant,
    name,
    encode(extensions.digest(token, 'sha256'), 'hex'),
    verify,
    null,
    case when secret is null then null else vault.create_secret(secret, 'webhook-in:' || v_id::text || ':' || gen_random_uuid()::text, 'better-supabase incoming webhook secret') end,
    case verify
      when 'hmac-sha256' then coalesce(signature_header, null, 'x-signature')
      when 'shared-secret' then coalesce(signature_header, null, 'x-webhook-secret')
    end,
    coalesce(metadata, '{}'),
    subject_type,
    subject_id,
    auth.uid())
  returning * into created;
  null;
  return jsonb_build_object('id', created."id", 'tenant', created."tenant", 'name', created."name",
    'verify', created."verify", 'token', token, 'secret', secret, 'signatureHeader', created."signature_header",
    'subjectType', created."subject_type", 'subjectId', created."subject_id");
end;
$$;

-- A new token (the old URL stops working); with rotate_secret, a new secret too.
create or replace function "better_supabase"."rotate_incoming_webhook"(endpoint uuid, rotate_secret boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  token text := encode(extensions.gen_random_bytes(24), 'hex');
  v_secret text;
  updated "better_supabase"."incoming_webhooks";
  previous "better_supabase"."incoming_webhooks";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into previous from "better_supabase"."incoming_webhooks" e where e."id" = endpoint for update;
  if previous."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), previous."tenant", 'webhooks.manage'), false)) then
    raise exception 'No incoming webhook %', endpoint using errcode = 'P0002', hint = 'WEBHOOK_IN_NOT_FOUND';
  end if;
  if rotate_secret then
    v_secret := case previous."verify"
    when 'standard-webhooks' then 'whsec_' || encode(extensions.gen_random_bytes(32), 'base64')
    when 'hmac-sha256' then encode(extensions.gen_random_bytes(32), 'hex')
    when 'shared-secret' then encode(extensions.gen_random_bytes(32), 'hex')
  end;
  end if;
  update "better_supabase"."incoming_webhooks" e set "token_hash" = encode(extensions.digest(token, 'sha256'), 'hex'),
    "secret" = case when rotate_secret then null else e."secret" end,
    "secret_id" = case when rotate_secret then case when v_secret is null then null else vault.create_secret(v_secret, 'webhook-in:' || e."id"::text || ':' || gen_random_uuid()::text, 'better-supabase incoming webhook secret') end else e."secret_id" end,
    "previous_secret" = case when rotate_secret then null else e."previous_secret" end,
    "previous_secret_id" = case when rotate_secret then null else e."previous_secret_id" end,
    "previous_secret_expires_at" = case when rotate_secret then null else e."previous_secret_expires_at" end
  where e."id" = endpoint
  returning * into updated;
  if rotate_secret then
    delete from vault.secrets vs where vs.id in (previous."secret_id", previous."previous_secret_id");
  end if;
  null;
  return jsonb_build_object('id', updated."id", 'token', token, 'secret', v_secret);
end;
$$;

create or replace function "better_supabase"."rotate_incoming_webhook_secret"(endpoint uuid, grace interval default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  previous "better_supabase"."incoming_webhooks";
  updated "better_supabase"."incoming_webhooks";
  v_secret text;
  v_keep boolean := coalesce(grace > interval '0', false);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into previous from "better_supabase"."incoming_webhooks" e where e."id" = endpoint for update;
  if previous."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), previous."tenant", 'webhooks.manage'), false)) then
    raise exception 'No incoming webhook %', endpoint using errcode = 'P0002', hint = 'WEBHOOK_IN_NOT_FOUND';
  end if;
  v_secret := case previous."verify"
    when 'standard-webhooks' then 'whsec_' || encode(extensions.gen_random_bytes(32), 'base64')
    when 'hmac-sha256' then encode(extensions.gen_random_bytes(32), 'hex')
    when 'shared-secret' then encode(extensions.gen_random_bytes(32), 'hex')
  end;
  if v_secret is null then
    raise exception 'This endpoint verifies no secret' using errcode = '22023', hint = 'WEBHOOK_IN_NO_SECRET';
  end if;
  update "better_supabase"."incoming_webhooks" e set
    "secret" = null,
    "secret_id" = case when v_secret is null then null else vault.create_secret(v_secret, 'webhook-in:' || e."id"::text || ':' || gen_random_uuid()::text, 'better-supabase incoming webhook secret') end,
    "previous_secret" = case when v_keep then e."secret" end,
    "previous_secret_id" = case when v_keep then e."secret_id" end,
    "previous_secret_expires_at" = case when v_keep then now() + grace end
  where e."id" = endpoint
  returning * into updated;
  delete from vault.secrets vs
  where vs.id = previous."previous_secret_id" or (not v_keep and vs.id = previous."secret_id");
  null;
  return jsonb_build_object('id', updated."id", 'secret', v_secret, 'previousSecretExpiresAt', updated."previous_secret_expires_at");
end;
$$;

create or replace function "better_supabase"."update_incoming_webhook"(
  endpoint uuid,
  name text default null,
  metadata jsonb default null,
  verify text default null,
  signature_header text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  previous "better_supabase"."incoming_webhooks";
  updated "better_supabase"."incoming_webhooks";
  v_verify text;
  v_secret text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into previous from "better_supabase"."incoming_webhooks" e where e."id" = endpoint for update;
  if previous."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), previous."tenant", 'webhooks.manage'), false)) then
    raise exception 'No incoming webhook %', endpoint using errcode = 'P0002', hint = 'WEBHOOK_IN_NOT_FOUND';
  end if;
  if name is not null and btrim(name) = '' then
    raise exception 'An endpoint needs a name' using errcode = '22023', hint = 'WEBHOOK_IN_NAME_REQUIRED';
  end if;
  if metadata is not null and jsonb_typeof(metadata) <> 'object' then
    raise exception 'metadata must be a JSON object' using errcode = '22023', hint = 'WEBHOOK_IN_METADATA_INVALID';
  end if;
  v_verify := coalesce(verify, previous."verify");
  if v_verify not in ('none', 'standard-webhooks', 'hmac-sha256', 'shared-secret') then
    raise exception 'Unknown verification mode' using errcode = '22023', hint = 'WEBHOOK_IN_VERIFY_UNKNOWN';
  end if;
  if v_verify <> previous."verify" then
    v_secret := case v_verify
    when 'standard-webhooks' then 'whsec_' || encode(extensions.gen_random_bytes(32), 'base64')
    when 'hmac-sha256' then encode(extensions.gen_random_bytes(32), 'hex')
    when 'shared-secret' then encode(extensions.gen_random_bytes(32), 'hex')
  end;
  end if;
  update "better_supabase"."incoming_webhooks" e set
    "name" = coalesce(update_incoming_webhook.name, e."name"),
    "metadata" = coalesce(update_incoming_webhook.metadata, e."metadata"),
    "verify" = v_verify,
    "secret" = case when v_verify = previous."verify" then e."secret" else null end,
    "secret_id" = case when v_verify = previous."verify" then e."secret_id" else case when v_secret is null then null else vault.create_secret(v_secret, 'webhook-in:' || e."id"::text || ':' || gen_random_uuid()::text, 'better-supabase incoming webhook secret') end end,
    "previous_secret" = case when v_verify = previous."verify" then e."previous_secret" end,
    "previous_secret_id" = case when v_verify = previous."verify" then e."previous_secret_id" end,
    "previous_secret_expires_at" = case when v_verify = previous."verify" then e."previous_secret_expires_at" end,
    "signature_header" = case v_verify
      when 'hmac-sha256' then coalesce(update_incoming_webhook.signature_header, case when v_verify = previous."verify" then e."signature_header" end, 'x-signature')
      when 'shared-secret' then coalesce(update_incoming_webhook.signature_header, case when v_verify = previous."verify" then e."signature_header" end, 'x-webhook-secret')
    end
  where e."id" = endpoint
  returning * into updated;
  if v_verify <> previous."verify" then
    delete from vault.secrets vs where vs.id in (previous."secret_id", previous."previous_secret_id");
  end if;
  null;
  return jsonb_build_object('id', updated."id", 'tenant', updated."tenant", 'name', updated."name",
    'verify', updated."verify", 'secret', v_secret, 'signatureHeader', updated."signature_header",
    'metadata', updated."metadata");
end;
$$;

create or replace function "better_supabase"."set_incoming_webhook_enabled"(endpoint uuid, enabled boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select e."tenant" into tenant from "better_supabase"."incoming_webhooks" e where e."id" = endpoint;
  if tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), tenant, 'webhooks.manage'), false)) then
    return false;
  end if;
  update "better_supabase"."incoming_webhooks" e set "enabled" = set_incoming_webhook_enabled.enabled where e."id" = endpoint;
  null;
  return true;
end;
$$;

create or replace function "better_supabase"."delete_incoming_webhook"(endpoint uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select e."tenant" into tenant from "better_supabase"."incoming_webhooks" e where e."id" = endpoint;
  if tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), tenant, 'webhooks.manage'), false)) then
    return false;
  end if;
  delete from "better_supabase"."incoming_webhooks" e where e."id" = endpoint;
  null;
  return true;
end;
$$;

-- The endpoint behind a token, with its secret and metadata, for the
-- receiving route.
drop function if exists "better_supabase"."incoming_webhook_by_token"(text);
create or replace function "better_supabase"."incoming_webhook_by_token"(token text)
returns table (id uuid, tenant text, enabled boolean, verify text, secret text, signature_header text, max_body_bytes integer, previous_secret text, metadata jsonb)
language sql
stable
security definer
set search_path = ''
as $$
  select e."id", e."tenant"::text, e."enabled", e."verify", coalesce(ds.decrypted_secret, e."secret"), e."signature_header", e."max_body_bytes",
    case when e."previous_secret_expires_at" > now() then coalesce(dp.decrypted_secret, e."previous_secret") end, e."metadata"
  from "better_supabase"."incoming_webhooks" e
  left join vault.decrypted_secrets ds on ds.id = e."secret_id"
  left join vault.decrypted_secrets dp on dp.id = e."previous_secret_id"
  where e."token_hash" = encode(extensions.digest(incoming_webhook_by_token.token, 'sha256'), 'hex')
$$;

-- Counts a delivery and keeps its HTTP status.
create or replace function "better_supabase"."record_incoming_webhook"(endpoint uuid, status integer)
returns void
language sql
security definer
set search_path = ''
as $$
  update "better_supabase"."incoming_webhooks" e
  set "receive_count" = e."receive_count" + 1, "last_received_at" = now(), "last_status" = record_incoming_webhook.status
  where e."id" = endpoint
$$;

revoke execute on function "better_supabase"."create_incoming_webhook"(uuid, text, text, jsonb, text, text, text) from public, anon;
grant execute on function "better_supabase"."create_incoming_webhook"(uuid, text, text, jsonb, text, text, text) to authenticated, service_role;
revoke execute on function "better_supabase"."rotate_incoming_webhook"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."rotate_incoming_webhook"(uuid, boolean) to authenticated, service_role;
revoke execute on function "better_supabase"."rotate_incoming_webhook_secret"(uuid, interval) from public, anon;
grant execute on function "better_supabase"."rotate_incoming_webhook_secret"(uuid, interval) to authenticated, service_role;
revoke execute on function "better_supabase"."update_incoming_webhook"(uuid, text, jsonb, text, text) from public, anon;
grant execute on function "better_supabase"."update_incoming_webhook"(uuid, text, jsonb, text, text) to authenticated, service_role;
revoke execute on function "better_supabase"."set_incoming_webhook_enabled"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."set_incoming_webhook_enabled"(uuid, boolean) to authenticated, service_role;
revoke execute on function "better_supabase"."delete_incoming_webhook"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_incoming_webhook"(uuid) to authenticated, service_role;
revoke execute on function "better_supabase"."incoming_webhook_by_token"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."incoming_webhook_by_token"(text) to service_role;
revoke execute on function "better_supabase"."record_incoming_webhook"(uuid, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."record_incoming_webhook"(uuid, integer) to service_role;

-- blocks.webhooks-in.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

-- Helpers for the module's policies and triggers have no entry point.
drop function if exists "api"."incoming_webhook_tenant_ids"();
drop function if exists "api"."incoming_webhook_subject_readable"(text, text, uuid);

drop function if exists "api"."create_incoming_webhook"(uuid, text, text, jsonb, text);
drop function if exists "api"."incoming_webhook_by_token"(text);

create or replace function "api"."actor_may_write"()
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."actor_may_write"() $$;
revoke execute on function "api"."actor_may_write"() from public;
grant execute on function "api"."actor_may_write"() to anon, authenticated, service_role;

create or replace function "api"."raise_actor_readonly"()
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."raise_actor_readonly"() $$;
revoke execute on function "api"."raise_actor_readonly"() from public;
grant execute on function "api"."raise_actor_readonly"() to anon, authenticated, service_role;

create or replace function "api"."list_incoming_webhooks"(tenant uuid, subject_type text default null, subject_id text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_incoming_webhooks"($1, $2, $3) $$;
revoke execute on function "api"."list_incoming_webhooks"(uuid, text, text) from public, anon;
grant execute on function "api"."list_incoming_webhooks"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."create_incoming_webhook"(tenant uuid, name text, verify text default 'none', metadata jsonb default '{}', signature_header text default null, subject_type text default null, subject_id text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_incoming_webhook"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."create_incoming_webhook"(uuid, text, text, jsonb, text, text, text) from public, anon;
grant execute on function "api"."create_incoming_webhook"(uuid, text, text, jsonb, text, text, text) to authenticated, service_role;

create or replace function "api"."rotate_incoming_webhook"(endpoint uuid, rotate_secret boolean default false)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."rotate_incoming_webhook"($1, $2) $$;
revoke execute on function "api"."rotate_incoming_webhook"(uuid, boolean) from public, anon;
grant execute on function "api"."rotate_incoming_webhook"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."rotate_incoming_webhook_secret"(endpoint uuid, grace interval default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."rotate_incoming_webhook_secret"($1, $2) $$;
revoke execute on function "api"."rotate_incoming_webhook_secret"(uuid, interval) from public, anon;
grant execute on function "api"."rotate_incoming_webhook_secret"(uuid, interval) to authenticated, service_role;

create or replace function "api"."update_incoming_webhook"(endpoint uuid, name text default null, metadata jsonb default null, verify text default null, signature_header text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_incoming_webhook"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."update_incoming_webhook"(uuid, text, jsonb, text, text) from public, anon;
grant execute on function "api"."update_incoming_webhook"(uuid, text, jsonb, text, text) to authenticated, service_role;

create or replace function "api"."set_incoming_webhook_enabled"(endpoint uuid, enabled boolean)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_incoming_webhook_enabled"($1, $2) $$;
revoke execute on function "api"."set_incoming_webhook_enabled"(uuid, boolean) from public, anon;
grant execute on function "api"."set_incoming_webhook_enabled"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."delete_incoming_webhook"(endpoint uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_incoming_webhook"($1) $$;
revoke execute on function "api"."delete_incoming_webhook"(uuid) from public, anon;
grant execute on function "api"."delete_incoming_webhook"(uuid) to authenticated, service_role;

create or replace function "api"."incoming_webhook_by_token"(token text)
returns table (id uuid, tenant text, enabled boolean, verify text, secret text, signature_header text, max_body_bytes integer, previous_secret text, metadata jsonb)
language sql
security invoker
set search_path = ''
as $$ select * from "better_supabase"."incoming_webhook_by_token"($1) $$;
revoke execute on function "api"."incoming_webhook_by_token"(text) from public, anon, authenticated;
grant execute on function "api"."incoming_webhook_by_token"(text) to service_role;

create or replace function "api"."record_incoming_webhook"(endpoint uuid, status integer)
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_incoming_webhook"($1, $2) $$;
revoke execute on function "api"."record_incoming_webhook"(uuid, integer) from public, anon, authenticated;
grant execute on function "api"."record_incoming_webhook"(uuid, integer) to service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_27_webhooks_in.sql
-- better-supabase module: webhooks-in
-- @bs-module-data webhooks-in
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('webhooks-in', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== adopt: schema supabase/schemas/900_better_supabase_27_webhooks_in.sql
-- better-supabase module: webhooks-in
-- @bs-module webhooks-in@4 adopt
-- Per-tenant trigger URLs with a hashed token, optional Standard Webhooks or HMAC verification, a body size limit, receive counters and the last status; deliveries go to the webhook inbox with the endpoint's tenant.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Trigger URLs over the app's table "better_supabase"."incoming_webhooks" (adopt mode): the app owns its
-- columns, indexes, grants and policies. Only the token's hash is kept.
-- Deleting an endpoint (or its tenant or subject) deletes its Vault secret.
create or replace function "better_supabase"."drop_incoming_webhook_secret"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from vault.secrets vs where vs.id in (old."secret_id", old."previous_secret_id");
  return null;
end;
$$;
revoke execute on function "better_supabase"."drop_incoming_webhook_secret"() from public, anon, authenticated;
drop trigger if exists "bsb_incoming_webhook_vault" on "better_supabase"."incoming_webhooks";
create trigger "bsb_incoming_webhook_vault" after delete on "better_supabase"."incoming_webhooks"
  for each row when (old."secret_id" is not null or old."previous_secret_id" is not null) execute function "better_supabase"."drop_incoming_webhook_secret"();

create or replace function "better_supabase"."incoming_webhook_tenant_ids"()
returns setof uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return query select better_supabase.tenant_ids_with('webhooks.read');
end;
$$;
revoke execute on function "better_supabase"."incoming_webhook_tenant_ids"() from public, anon;
grant execute on function "better_supabase"."incoming_webhook_tenant_ids"() to authenticated, service_role;
-- Whether the caller may read an endpoint's subject: its row is visible to
-- them (the subject table's own policies apply) and they hold its permission.
create or replace function "better_supabase"."incoming_webhook_subject_readable"(subject_type text, subject_id text, tenant uuid)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select subject_type is null or true
$$;
revoke execute on function "better_supabase"."incoming_webhook_subject_readable"(text, text, uuid) from public, anon;
grant execute on function "better_supabase"."incoming_webhook_subject_readable"(text, text, uuid) to authenticated, service_role;


-- A tenant's endpoints, or one subject's, without secrets; runs as the caller.
create or replace function "better_supabase"."list_incoming_webhooks"(tenant uuid, subject_type text default null, subject_id text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', e."id",
    'tenant', e."tenant",
    'name', e."name",
    'verify', e."verify",
    'signature_header', e."signature_header",
    'enabled', e."enabled",
    'max_body_bytes', e."max_body_bytes",
    'receive_count', e."receive_count",
    'last_received_at', e."last_received_at",
    'last_status', e."last_status",
    'metadata', e."metadata",
    'subject_type', e."subject_type",
    'subject_id', e."subject_id",
    'created_by', e."created_by",
    'created_at', e."created_at"
  ) order by e."created_at"), '[]'::jsonb)
  from "better_supabase"."incoming_webhooks" e
  where e."tenant" = list_incoming_webhooks.tenant
    and (list_incoming_webhooks.subject_type is null or e."subject_type" = list_incoming_webhooks.subject_type)
    and (list_incoming_webhooks.subject_id is null or e."subject_id" = list_incoming_webhooks.subject_id)
$$;
revoke execute on function "better_supabase"."list_incoming_webhooks"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."list_incoming_webhooks"(uuid, text, text) to authenticated, service_role;

drop function if exists "better_supabase"."create_incoming_webhook"(uuid, text, text, jsonb, text);
-- Creates an endpoint and returns it with its token (and the signing secret
-- for standard-webhooks and hmac-sha256), shown once.
create or replace function "better_supabase"."create_incoming_webhook"(
  tenant uuid,
  name text,
  verify text default 'none',
  metadata jsonb default '{}',
  signature_header text default null,
  subject_type text default null,
  subject_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid := gen_random_uuid();
  token text := encode(extensions.gen_random_bytes(24), 'hex');
  secret text := case verify
    when 'standard-webhooks' then 'whsec_' || encode(extensions.gen_random_bytes(32), 'base64')
    when 'hmac-sha256' then encode(extensions.gen_random_bytes(32), 'hex')
    when 'shared-secret' then encode(extensions.gen_random_bytes(32), 'hex')
  end;
  created "better_supabase"."incoming_webhooks";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), tenant, 'webhooks.manage'), false)) then
    raise exception 'Not allowed to manage incoming webhooks' using errcode = '42501', hint = 'WEBHOOK_IN_FORBIDDEN';
  end if;
  if verify not in ('none', 'standard-webhooks', 'hmac-sha256', 'shared-secret') then
    raise exception 'Unknown verification mode' using errcode = '22023', hint = 'WEBHOOK_IN_VERIFY_UNKNOWN';
  end if;
  if (subject_type is null) <> (subject_id is null) then
    raise exception 'Pass subject_type and subject_id together' using errcode = '22023', hint = 'WEBHOOK_IN_SUBJECT_INVALID';
  end if;
  if subject_type is not null and not (true) then
    raise exception 'No such subject in this tenant' using errcode = '22023', hint = 'WEBHOOK_IN_SUBJECT_INVALID';
  end if;
  insert into "better_supabase"."incoming_webhooks" ("id", "tenant", "name", "token_hash", "verify", "secret", "secret_id", "signature_header", "metadata", "subject_type", "subject_id", "created_by")
  values (v_id,
    tenant,
    name,
    encode(extensions.digest(token, 'sha256'), 'hex'),
    verify,
    null,
    case when secret is null then null else vault.create_secret(secret, 'webhook-in:' || v_id::text || ':' || gen_random_uuid()::text, 'better-supabase incoming webhook secret') end,
    case verify
      when 'hmac-sha256' then coalesce(signature_header, null, 'x-signature')
      when 'shared-secret' then coalesce(signature_header, null, 'x-webhook-secret')
    end,
    coalesce(metadata, '{}'),
    subject_type,
    subject_id,
    auth.uid())
  returning * into created;
  null;
  return jsonb_build_object('id', created."id", 'tenant', created."tenant", 'name', created."name",
    'verify', created."verify", 'token', token, 'secret', secret, 'signatureHeader', created."signature_header",
    'subjectType', created."subject_type", 'subjectId', created."subject_id");
end;
$$;

-- A new token (the old URL stops working); with rotate_secret, a new secret too.
create or replace function "better_supabase"."rotate_incoming_webhook"(endpoint uuid, rotate_secret boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  token text := encode(extensions.gen_random_bytes(24), 'hex');
  v_secret text;
  updated "better_supabase"."incoming_webhooks";
  previous "better_supabase"."incoming_webhooks";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into previous from "better_supabase"."incoming_webhooks" e where e."id" = endpoint for update;
  if previous."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), previous."tenant", 'webhooks.manage'), false)) then
    raise exception 'No incoming webhook %', endpoint using errcode = 'P0002', hint = 'WEBHOOK_IN_NOT_FOUND';
  end if;
  if rotate_secret then
    v_secret := case previous."verify"
    when 'standard-webhooks' then 'whsec_' || encode(extensions.gen_random_bytes(32), 'base64')
    when 'hmac-sha256' then encode(extensions.gen_random_bytes(32), 'hex')
    when 'shared-secret' then encode(extensions.gen_random_bytes(32), 'hex')
  end;
  end if;
  update "better_supabase"."incoming_webhooks" e set "token_hash" = encode(extensions.digest(token, 'sha256'), 'hex'),
    "secret" = case when rotate_secret then null else e."secret" end,
    "secret_id" = case when rotate_secret then case when v_secret is null then null else vault.create_secret(v_secret, 'webhook-in:' || e."id"::text || ':' || gen_random_uuid()::text, 'better-supabase incoming webhook secret') end else e."secret_id" end,
    "previous_secret" = case when rotate_secret then null else e."previous_secret" end,
    "previous_secret_id" = case when rotate_secret then null else e."previous_secret_id" end,
    "previous_secret_expires_at" = case when rotate_secret then null else e."previous_secret_expires_at" end
  where e."id" = endpoint
  returning * into updated;
  if rotate_secret then
    delete from vault.secrets vs where vs.id in (previous."secret_id", previous."previous_secret_id");
  end if;
  null;
  return jsonb_build_object('id', updated."id", 'token', token, 'secret', v_secret);
end;
$$;

create or replace function "better_supabase"."rotate_incoming_webhook_secret"(endpoint uuid, grace interval default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  previous "better_supabase"."incoming_webhooks";
  updated "better_supabase"."incoming_webhooks";
  v_secret text;
  v_keep boolean := coalesce(grace > interval '0', false);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into previous from "better_supabase"."incoming_webhooks" e where e."id" = endpoint for update;
  if previous."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), previous."tenant", 'webhooks.manage'), false)) then
    raise exception 'No incoming webhook %', endpoint using errcode = 'P0002', hint = 'WEBHOOK_IN_NOT_FOUND';
  end if;
  v_secret := case previous."verify"
    when 'standard-webhooks' then 'whsec_' || encode(extensions.gen_random_bytes(32), 'base64')
    when 'hmac-sha256' then encode(extensions.gen_random_bytes(32), 'hex')
    when 'shared-secret' then encode(extensions.gen_random_bytes(32), 'hex')
  end;
  if v_secret is null then
    raise exception 'This endpoint verifies no secret' using errcode = '22023', hint = 'WEBHOOK_IN_NO_SECRET';
  end if;
  update "better_supabase"."incoming_webhooks" e set
    "secret" = null,
    "secret_id" = case when v_secret is null then null else vault.create_secret(v_secret, 'webhook-in:' || e."id"::text || ':' || gen_random_uuid()::text, 'better-supabase incoming webhook secret') end,
    "previous_secret" = case when v_keep then e."secret" end,
    "previous_secret_id" = case when v_keep then e."secret_id" end,
    "previous_secret_expires_at" = case when v_keep then now() + grace end
  where e."id" = endpoint
  returning * into updated;
  delete from vault.secrets vs
  where vs.id = previous."previous_secret_id" or (not v_keep and vs.id = previous."secret_id");
  null;
  return jsonb_build_object('id', updated."id", 'secret', v_secret, 'previousSecretExpiresAt', updated."previous_secret_expires_at");
end;
$$;

create or replace function "better_supabase"."update_incoming_webhook"(
  endpoint uuid,
  name text default null,
  metadata jsonb default null,
  verify text default null,
  signature_header text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  previous "better_supabase"."incoming_webhooks";
  updated "better_supabase"."incoming_webhooks";
  v_verify text;
  v_secret text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into previous from "better_supabase"."incoming_webhooks" e where e."id" = endpoint for update;
  if previous."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), previous."tenant", 'webhooks.manage'), false)) then
    raise exception 'No incoming webhook %', endpoint using errcode = 'P0002', hint = 'WEBHOOK_IN_NOT_FOUND';
  end if;
  if name is not null and btrim(name) = '' then
    raise exception 'An endpoint needs a name' using errcode = '22023', hint = 'WEBHOOK_IN_NAME_REQUIRED';
  end if;
  if metadata is not null and jsonb_typeof(metadata) <> 'object' then
    raise exception 'metadata must be a JSON object' using errcode = '22023', hint = 'WEBHOOK_IN_METADATA_INVALID';
  end if;
  v_verify := coalesce(verify, previous."verify");
  if v_verify not in ('none', 'standard-webhooks', 'hmac-sha256', 'shared-secret') then
    raise exception 'Unknown verification mode' using errcode = '22023', hint = 'WEBHOOK_IN_VERIFY_UNKNOWN';
  end if;
  if v_verify <> previous."verify" then
    v_secret := case v_verify
    when 'standard-webhooks' then 'whsec_' || encode(extensions.gen_random_bytes(32), 'base64')
    when 'hmac-sha256' then encode(extensions.gen_random_bytes(32), 'hex')
    when 'shared-secret' then encode(extensions.gen_random_bytes(32), 'hex')
  end;
  end if;
  update "better_supabase"."incoming_webhooks" e set
    "name" = coalesce(update_incoming_webhook.name, e."name"),
    "metadata" = coalesce(update_incoming_webhook.metadata, e."metadata"),
    "verify" = v_verify,
    "secret" = case when v_verify = previous."verify" then e."secret" else null end,
    "secret_id" = case when v_verify = previous."verify" then e."secret_id" else case when v_secret is null then null else vault.create_secret(v_secret, 'webhook-in:' || e."id"::text || ':' || gen_random_uuid()::text, 'better-supabase incoming webhook secret') end end,
    "previous_secret" = case when v_verify = previous."verify" then e."previous_secret" end,
    "previous_secret_id" = case when v_verify = previous."verify" then e."previous_secret_id" end,
    "previous_secret_expires_at" = case when v_verify = previous."verify" then e."previous_secret_expires_at" end,
    "signature_header" = case v_verify
      when 'hmac-sha256' then coalesce(update_incoming_webhook.signature_header, case when v_verify = previous."verify" then e."signature_header" end, 'x-signature')
      when 'shared-secret' then coalesce(update_incoming_webhook.signature_header, case when v_verify = previous."verify" then e."signature_header" end, 'x-webhook-secret')
    end
  where e."id" = endpoint
  returning * into updated;
  if v_verify <> previous."verify" then
    delete from vault.secrets vs where vs.id in (previous."secret_id", previous."previous_secret_id");
  end if;
  null;
  return jsonb_build_object('id', updated."id", 'tenant', updated."tenant", 'name', updated."name",
    'verify', updated."verify", 'secret', v_secret, 'signatureHeader', updated."signature_header",
    'metadata', updated."metadata");
end;
$$;

create or replace function "better_supabase"."set_incoming_webhook_enabled"(endpoint uuid, enabled boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select e."tenant" into tenant from "better_supabase"."incoming_webhooks" e where e."id" = endpoint;
  if tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), tenant, 'webhooks.manage'), false)) then
    return false;
  end if;
  update "better_supabase"."incoming_webhooks" e set "enabled" = set_incoming_webhook_enabled.enabled where e."id" = endpoint;
  null;
  return true;
end;
$$;

create or replace function "better_supabase"."delete_incoming_webhook"(endpoint uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select e."tenant" into tenant from "better_supabase"."incoming_webhooks" e where e."id" = endpoint;
  if tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), tenant, 'webhooks.manage'), false)) then
    return false;
  end if;
  delete from "better_supabase"."incoming_webhooks" e where e."id" = endpoint;
  null;
  return true;
end;
$$;

-- The endpoint behind a token, with its secret and metadata, for the
-- receiving route.
drop function if exists "better_supabase"."incoming_webhook_by_token"(text);
create or replace function "better_supabase"."incoming_webhook_by_token"(token text)
returns table (id uuid, tenant text, enabled boolean, verify text, secret text, signature_header text, max_body_bytes integer, previous_secret text, metadata jsonb)
language sql
stable
security definer
set search_path = ''
as $$
  select e."id", e."tenant"::text, e."enabled", e."verify", coalesce(ds.decrypted_secret, e."secret"), e."signature_header", e."max_body_bytes",
    case when e."previous_secret_expires_at" > now() then coalesce(dp.decrypted_secret, e."previous_secret") end, e."metadata"
  from "better_supabase"."incoming_webhooks" e
  left join vault.decrypted_secrets ds on ds.id = e."secret_id"
  left join vault.decrypted_secrets dp on dp.id = e."previous_secret_id"
  where e."token_hash" = encode(extensions.digest(incoming_webhook_by_token.token, 'sha256'), 'hex')
$$;

-- Counts a delivery and keeps its HTTP status.
create or replace function "better_supabase"."record_incoming_webhook"(endpoint uuid, status integer)
returns void
language sql
security definer
set search_path = ''
as $$
  update "better_supabase"."incoming_webhooks" e
  set "receive_count" = e."receive_count" + 1, "last_received_at" = now(), "last_status" = record_incoming_webhook.status
  where e."id" = endpoint
$$;

revoke execute on function "better_supabase"."create_incoming_webhook"(uuid, text, text, jsonb, text, text, text) from public, anon;
grant execute on function "better_supabase"."create_incoming_webhook"(uuid, text, text, jsonb, text, text, text) to authenticated, service_role;
revoke execute on function "better_supabase"."rotate_incoming_webhook"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."rotate_incoming_webhook"(uuid, boolean) to authenticated, service_role;
revoke execute on function "better_supabase"."rotate_incoming_webhook_secret"(uuid, interval) from public, anon;
grant execute on function "better_supabase"."rotate_incoming_webhook_secret"(uuid, interval) to authenticated, service_role;
revoke execute on function "better_supabase"."update_incoming_webhook"(uuid, text, jsonb, text, text) from public, anon;
grant execute on function "better_supabase"."update_incoming_webhook"(uuid, text, jsonb, text, text) to authenticated, service_role;
revoke execute on function "better_supabase"."set_incoming_webhook_enabled"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."set_incoming_webhook_enabled"(uuid, boolean) to authenticated, service_role;
revoke execute on function "better_supabase"."delete_incoming_webhook"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_incoming_webhook"(uuid) to authenticated, service_role;
revoke execute on function "better_supabase"."incoming_webhook_by_token"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."incoming_webhook_by_token"(text) to service_role;
revoke execute on function "better_supabase"."record_incoming_webhook"(uuid, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."record_incoming_webhook"(uuid, integer) to service_role;

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

-- ==== adopt: data supabase/better-supabase-data/900_better_supabase_27_webhooks_in.sql
-- better-supabase module: webhooks-in
-- @bs-module-data webhooks-in
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('webhooks-in', 4, 'adopt')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
