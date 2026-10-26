-- better-supabase module: webhooks-in
-- @bsb-block webhooks-in@4 managed
-- @bsb-hash sha256:fae87e9496f93cd5eea0b27582c4fbefaae06ed937f21482dd1f9968cba5216e
-- Per-tenant trigger URLs with a hashed token, optional Standard Webhooks or HMAC verification, a body size limit, receive counters and the last status; deliveries go to the webhook inbox with the endpoint's tenant.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
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
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "centrakit"."inbound_webhooks";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Trigger URLs over the app's table "centrakit"."inbound_webhooks" (the app's table): the app owns its
-- columns, indexes, grants and policies. Only the token's hash is kept.
-- Deleting an endpoint (or its tenant or subject) deletes its Vault secret.
create or replace function "better_supabase"."drop_incoming_webhook_secret"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from vault.secrets vs where vs.id in (old."vault_secret_id");
  return null;
end;
$$;
revoke execute on function "better_supabase"."drop_incoming_webhook_secret"() from public, anon, authenticated;
drop trigger if exists "bsb_incoming_webhook_vault" on "centrakit"."inbound_webhooks";
create trigger "bsb_incoming_webhook_vault" after delete on "centrakit"."inbound_webhooks"
  for each row when (old."vault_secret_id" is not null) execute function "better_supabase"."drop_incoming_webhook_secret"();

create or replace function "better_supabase"."incoming_webhook_tenant_ids"()
returns setof uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return query select better_supabase.tenant_ids_with('webhook.view');
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
    'tenant', e."organization_id",
    'name', e."name",
    'verify', e."verification",
    'signature_header', e."signature_header",
    'enabled', e."enabled",
    'max_body_bytes', 1048576,
    'receive_count', 0,
    'last_received_at', null,
    'last_status', null,
    'metadata', e."settings",
    'subject_type', null,
    'subject_id', null,
    'created_by', e."created_by",
    'created_at', e."created_at"
  ) order by e."created_at"), '[]'::jsonb)
  from "centrakit"."inbound_webhooks" e
  where e."organization_id" = list_incoming_webhooks.tenant
    and list_incoming_webhooks.subject_type is null and list_incoming_webhooks.subject_id is null
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
  created "centrakit"."inbound_webhooks";
begin
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), tenant, 'webhook.manage'), false)) then
    raise exception 'Not allowed to manage incoming webhooks' using errcode = '42501', hint = 'WEBHOOK_IN_FORBIDDEN';
  end if;
  if verify not in ('none', 'standard-webhooks', 'hmac-sha256', 'shared-secret') then
    raise exception 'Unknown verification mode' using errcode = '22023', hint = 'WEBHOOK_IN_VERIFY_UNKNOWN';
  end if;
  if subject_type is not null or subject_id is not null then
    raise exception 'This endpoints table has no subject columns' using errcode = '22023', hint = 'WEBHOOK_IN_SUBJECT_INVALID';
  end if;
  if (subject_type is null) <> (subject_id is null) then
    raise exception 'Pass subject_type and subject_id together' using errcode = '22023', hint = 'WEBHOOK_IN_SUBJECT_INVALID';
  end if;
  if subject_type is not null and not (true) then
    raise exception 'No such subject in this tenant' using errcode = '22023', hint = 'WEBHOOK_IN_SUBJECT_INVALID';
  end if;
  insert into "centrakit"."inbound_webhooks" ("id", "organization_id", "name", "token_digest", "verification", "vault_secret_id", "signature_header", "settings", "created_by")
  values (v_id,
    tenant,
    name,
    encode(extensions.digest(token, 'sha256'), 'hex'),
    verify,
    case when secret is null then null else vault.create_secret(secret, 'webhook-in:' || v_id::text || ':' || gen_random_uuid()::text, 'better-supabase incoming webhook secret') end,
    case verify
      when 'hmac-sha256' then coalesce(signature_header, null, 'x-signature')
      when 'shared-secret' then coalesce(signature_header, null, 'x-webhook-secret')
    end,
    coalesce(metadata, '{}'),
    auth.uid())
  returning * into created;
  perform "better_supabase".emit_event('incoming_webhook.created', jsonb_build_object('organizationId', created."organization_id"::text, 'endpointId', created."id", 'name', created."name"), 'organizations/' || created."organization_id"::text || '/incoming-webhooks/' || created."id"::text, (created."organization_id")::text, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'incoming_webhook.created',
    category => 'integration',
    target_type => 'incoming_webhook',
    record_id => created."id"::text,
    tenant => (created."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', created."organization_id"::text, 'endpointId', created."id", 'name', created."name")
  );
  return jsonb_build_object('id', created."id", 'tenant', created."organization_id", 'name', created."name",
    'verify', created."verification", 'token', token, 'secret', secret, 'signatureHeader', created."signature_header",
    'subjectType', null, 'subjectId', null);
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
  updated "centrakit"."inbound_webhooks";
  previous "centrakit"."inbound_webhooks";
begin
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into previous from "centrakit"."inbound_webhooks" e where e."id" = endpoint for update;
  if previous."id" is null or not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), previous."organization_id", 'webhook.manage'), false)) then
    raise exception 'No incoming webhook %', endpoint using errcode = 'P0002', hint = 'WEBHOOK_IN_NOT_FOUND';
  end if;
  if rotate_secret then
    v_secret := case previous."verification"
    when 'standard-webhooks' then 'whsec_' || encode(extensions.gen_random_bytes(32), 'base64')
    when 'hmac-sha256' then encode(extensions.gen_random_bytes(32), 'hex')
    when 'shared-secret' then encode(extensions.gen_random_bytes(32), 'hex')
  end;
  end if;
  update "centrakit"."inbound_webhooks" e set "token_digest" = encode(extensions.digest(token, 'sha256'), 'hex'),
    "vault_secret_id" = case when rotate_secret then case when v_secret is null then null else vault.create_secret(v_secret, 'webhook-in:' || e."id"::text || ':' || gen_random_uuid()::text, 'better-supabase incoming webhook secret') end else e."vault_secret_id" end
  where e."id" = endpoint
  returning * into updated;
  if rotate_secret then
    delete from vault.secrets vs where vs.id in (previous."vault_secret_id");
  end if;
  perform "better_supabase".emit_event('incoming_webhook.token_rotated', jsonb_build_object('organizationId', updated."organization_id"::text, 'endpointId', updated."id", 'secretRotated', rotate_secret), 'organizations/' || updated."organization_id"::text || '/incoming-webhooks/' || updated."id"::text, (updated."organization_id")::text, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'incoming_webhook.token_rotated',
    category => 'security',
    target_type => 'incoming_webhook',
    record_id => updated."id"::text,
    tenant => (updated."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', updated."organization_id"::text, 'endpointId', updated."id", 'secretRotated', rotate_secret)
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
  previous "centrakit"."inbound_webhooks";
  updated "centrakit"."inbound_webhooks";
  v_secret text;
  v_keep boolean := coalesce(grace > interval '0', false);
begin
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into previous from "centrakit"."inbound_webhooks" e where e."id" = endpoint for update;
  if previous."id" is null or not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), previous."organization_id", 'webhook.manage'), false)) then
    raise exception 'No incoming webhook %', endpoint using errcode = 'P0002', hint = 'WEBHOOK_IN_NOT_FOUND';
  end if;
  v_secret := case previous."verification"
    when 'standard-webhooks' then 'whsec_' || encode(extensions.gen_random_bytes(32), 'base64')
    when 'hmac-sha256' then encode(extensions.gen_random_bytes(32), 'hex')
    when 'shared-secret' then encode(extensions.gen_random_bytes(32), 'hex')
  end;
  if v_secret is null then
    raise exception 'This endpoint verifies no secret' using errcode = '22023', hint = 'WEBHOOK_IN_NO_SECRET';
  end if;
  if v_keep then
    raise exception 'This endpoints table has no previous-secret columns, so a rotation can''t keep the old secret' using errcode = '22023', hint = 'WEBHOOK_IN_NO_GRACE';
  end if;
  update "centrakit"."inbound_webhooks" e set
    "vault_secret_id" = case when v_secret is null then null else vault.create_secret(v_secret, 'webhook-in:' || e."id"::text || ':' || gen_random_uuid()::text, 'better-supabase incoming webhook secret') end
  where e."id" = endpoint
  returning * into updated;
  delete from vault.secrets vs where vs.id = previous."vault_secret_id";
  perform "better_supabase".emit_event('incoming_webhook.secret_rotated', jsonb_build_object('organizationId', updated."organization_id"::text, 'endpointId', updated."id"), 'organizations/' || updated."organization_id"::text || '/incoming-webhooks/' || updated."id"::text, (updated."organization_id")::text, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'incoming_webhook.secret_rotated',
    category => 'security',
    target_type => 'incoming_webhook',
    record_id => updated."id"::text,
    tenant => (updated."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', updated."organization_id"::text, 'endpointId', updated."id")
  );
  return jsonb_build_object('id', updated."id", 'secret', v_secret, 'previousSecretExpiresAt', null);
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
  previous "centrakit"."inbound_webhooks";
  updated "centrakit"."inbound_webhooks";
  v_verify text;
  v_secret text;
begin
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into previous from "centrakit"."inbound_webhooks" e where e."id" = endpoint for update;
  if previous."id" is null or not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), previous."organization_id", 'webhook.manage'), false)) then
    raise exception 'No incoming webhook %', endpoint using errcode = 'P0002', hint = 'WEBHOOK_IN_NOT_FOUND';
  end if;
  if name is not null and btrim(name) = '' then
    raise exception 'An endpoint needs a name' using errcode = '22023', hint = 'WEBHOOK_IN_NAME_REQUIRED';
  end if;
  if metadata is not null and jsonb_typeof(metadata) <> 'object' then
    raise exception 'metadata must be a JSON object' using errcode = '22023', hint = 'WEBHOOK_IN_METADATA_INVALID';
  end if;
  v_verify := coalesce(verify, previous."verification");
  if v_verify not in ('none', 'standard-webhooks', 'hmac-sha256', 'shared-secret') then
    raise exception 'Unknown verification mode' using errcode = '22023', hint = 'WEBHOOK_IN_VERIFY_UNKNOWN';
  end if;
  if v_verify <> previous."verification" then
    v_secret := case v_verify
    when 'standard-webhooks' then 'whsec_' || encode(extensions.gen_random_bytes(32), 'base64')
    when 'hmac-sha256' then encode(extensions.gen_random_bytes(32), 'hex')
    when 'shared-secret' then encode(extensions.gen_random_bytes(32), 'hex')
  end;
  end if;
  update "centrakit"."inbound_webhooks" e set
    "name" = coalesce(update_incoming_webhook.name, e."name"),
    "settings" = coalesce(update_incoming_webhook.metadata, e."settings"),
    "verification" = v_verify,
    "vault_secret_id" = case when v_verify = previous."verification" then e."vault_secret_id" else case when v_secret is null then null else vault.create_secret(v_secret, 'webhook-in:' || e."id"::text || ':' || gen_random_uuid()::text, 'better-supabase incoming webhook secret') end end,
    "signature_header" = case v_verify
      when 'hmac-sha256' then coalesce(update_incoming_webhook.signature_header, case when v_verify = previous."verification" then e."signature_header" end, 'x-signature')
      when 'shared-secret' then coalesce(update_incoming_webhook.signature_header, case when v_verify = previous."verification" then e."signature_header" end, 'x-webhook-secret')
    end
  where e."id" = endpoint
  returning * into updated;
  if v_verify <> previous."verification" then
    delete from vault.secrets vs where vs.id in (previous."vault_secret_id");
  end if;
  perform "better_supabase".emit_event('incoming_webhook.updated', jsonb_build_object('organizationId', updated."organization_id"::text, 'endpointId', updated."id", 'name', updated."name", 'verify', updated."verification"), 'organizations/' || updated."organization_id"::text || '/incoming-webhooks/' || updated."id"::text, (updated."organization_id")::text, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'incoming_webhook.updated',
    category => 'integration',
    target_type => 'incoming_webhook',
    record_id => updated."id"::text,
    tenant => (updated."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', updated."organization_id"::text, 'endpointId', updated."id", 'name', updated."name", 'verify', updated."verification")
  );
  return jsonb_build_object('id', updated."id", 'tenant', updated."organization_id", 'name', updated."name",
    'verify', updated."verification", 'secret', v_secret, 'signatureHeader', updated."signature_header",
    'metadata', updated."settings");
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
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select e."organization_id" into tenant from "centrakit"."inbound_webhooks" e where e."id" = endpoint;
  if tenant is null or not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), tenant, 'webhook.manage'), false)) then
    return false;
  end if;
  update "centrakit"."inbound_webhooks" e set "enabled" = set_incoming_webhook_enabled.enabled where e."id" = endpoint;
  perform "better_supabase".emit_event('incoming_webhook.enabled_set', jsonb_build_object('organizationId', tenant::text, 'endpointId', endpoint, 'enabled', set_incoming_webhook_enabled.enabled), 'organizations/' || tenant::text || '/incoming-webhooks/' || endpoint::text, (tenant)::text, null, 'domain');
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
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select e."organization_id" into tenant from "centrakit"."inbound_webhooks" e where e."id" = endpoint;
  if tenant is null or not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), tenant, 'webhook.manage'), false)) then
    return false;
  end if;
  delete from "centrakit"."inbound_webhooks" e where e."id" = endpoint;
  perform "better_supabase".emit_event('incoming_webhook.deleted', jsonb_build_object('organizationId', tenant::text, 'endpointId', endpoint), 'organizations/' || tenant::text || '/incoming-webhooks/' || endpoint::text, (tenant)::text, null, 'domain');
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
  select e."id", e."organization_id"::text, e."enabled", e."verification", ds.decrypted_secret, e."signature_header", 1048576,
    null::text, e."settings"
  from "centrakit"."inbound_webhooks" e
  left join vault.decrypted_secrets ds on ds.id = e."vault_secret_id"
  where e."token_digest" = encode(extensions.digest(incoming_webhook_by_token.token, 'sha256'), 'hex')
$$;

-- Counts a delivery and keeps its HTTP status.
create or replace function "better_supabase"."record_incoming_webhook"(endpoint uuid, status integer)
returns void
language sql
security definer
set search_path = ''
as $$
  select
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
