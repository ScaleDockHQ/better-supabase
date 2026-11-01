-- ==== alone: schema supabase/schemas/900_better_supabase_171_agent_checkout.sql
-- better-supabase module: agent-checkout
-- @bsb-block agent-checkout@1 managed
-- @bsb-hash sha256:8e05ea94a635a2ca8951974d23d2c6f14b9915210385f29169acb431aeafb173
-- ACP and UCP checkout sessions over an orders cart with idempotency keys, and AP2 checkout mandates verified with signing keys and used once.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."checkout_sessions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."checkout_sessions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."checkout_sessions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."checkout_sessions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."checkout_sessions";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."agent_mandates";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."agent_mandates";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."agent_mandates";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."agent_mandates";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."agent_mandates";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Agent checkout: ACP and UCP checkout sessions over an orders cart, and AP2
-- mandates stored beside them. The session keeps the protocol state; the cart
-- and the order keep the money (bigint minor units).
create table if not exists "better_supabase"."checkout_sessions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "cart_id" uuid not null,
  "protocol" text not null check ("protocol" in ('acp', 'ucp')),
  "status" text not null default 'open' check ("status" in ('open', 'ready', 'completed', 'canceled')),
  "idempotency_key" text not null check (length("idempotency_key") between 1 and 255),
  "request_hash" text not null check (length("request_hash") between 1 and 128),
  "buyer" jsonb,
  "order_id" uuid,
  "expires_at" timestamptz,
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "idempotency_key"),
  check (("status" = 'completed') = ("order_id" is not null))
);
create index if not exists "checkout_sessions_cart_idx" on "better_supabase"."checkout_sessions" ("cart_id");
alter table "better_supabase"."checkout_sessions" enable row level security;
revoke all on "better_supabase"."checkout_sessions" from public, anon, authenticated;
grant select on "better_supabase"."checkout_sessions" to authenticated;
grant all on "better_supabase"."checkout_sessions" to service_role;
drop policy if exists checkout_sessions_read on "better_supabase"."checkout_sessions";
create policy checkout_sessions_read on "better_supabase"."checkout_sessions"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('agent_checkout.read')));

-- A mandate an agent presents: the compact credential, its hash and the key
-- that signed it. The TypeScript side verifies the signature with the
-- signing-keys block before it stores the row; closed mandates are used once.
create table if not exists "better_supabase"."agent_mandates" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "session_id" uuid references "better_supabase"."checkout_sessions" ("id") on delete set null,
  "vct" text not null check ("vct" in ('mandate.checkout.open.1', 'mandate.checkout.1')),
  "status" text not null default 'active' check ("status" in ('active', 'consumed', 'revoked')),
  "credential" text not null check (length("credential") between 1 and 16384),
  "credential_hash" text not null check (length("credential_hash") between 1 and 128),
  "issuer_kid" text,
  "subject" text,
  "expires_at" timestamptz not null,
  "consumed_at" timestamptz,
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "credential_hash"),
  check (("status" = 'consumed') = ("consumed_at" is not null))
);
create index if not exists "agent_mandates_session_idx" on "better_supabase"."agent_mandates" ("session_id");
alter table "better_supabase"."agent_mandates" enable row level security;
revoke all on "better_supabase"."agent_mandates" from public, anon, authenticated;
grant select on "better_supabase"."agent_mandates" to authenticated;
grant all on "better_supabase"."agent_mandates" to service_role;
drop policy if exists agent_mandates_read on "better_supabase"."agent_mandates";
create policy agent_mandates_read on "better_supabase"."agent_mandates"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('agent_checkout.read')));

-- Starts a checkout session over a cart, or returns the one this idempotency
-- key made before (replayed true). The same key with another request_hash
-- fails with CHECKOUT_IDEMPOTENCY_CONFLICT. Needs agent_checkout.write.
create or replace function "better_supabase"."create_checkout_session"(tenant uuid, cart_id uuid, protocol text, idempotency_key text, request_hash text, expires_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."checkout_sessions";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_checkout_session.tenant is not null and coalesce(better_supabase.can('tenant', create_checkout_session.tenant, 'agent_checkout.write'), false))) then
    raise exception 'not allowed to start checkout sessions' using errcode = '42501', hint = 'CHECKOUT_FORBIDDEN';
  end if;
  if create_checkout_session.protocol is null or create_checkout_session.protocol not in ('acp', 'ucp') then
    raise exception 'the protocol is acp or ucp' using errcode = '22023', hint = 'CHECKOUT_INVALID';
  end if;
  if coalesce(create_checkout_session.idempotency_key, '') = '' or coalesce(create_checkout_session.request_hash, '') = '' then
    raise exception 'a checkout session needs an idempotency key' using errcode = '22023', hint = 'CHECKOUT_IDEMPOTENCY_KEY_REQUIRED';
  end if;
  select * into v_row from "better_supabase"."checkout_sessions" x
  where x."tenant_id" = create_checkout_session.tenant and x."idempotency_key" = create_checkout_session.idempotency_key;
  if found then
    if v_row."request_hash" <> create_checkout_session.request_hash then
      raise exception 'this idempotency key was used with another request' using errcode = '22023', hint = 'CHECKOUT_IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status", 'buyer', v_row."buyer", 'orderId', v_row."order_id", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" in ('open', 'ready') and v_row."expires_at" is not null and v_row."expires_at" <= now()), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('replayed', true);
  end if;
  begin
    insert into "better_supabase"."checkout_sessions" ("tenant_id", "cart_id", "protocol", "idempotency_key", "request_hash", "expires_at")
    values (create_checkout_session.tenant, create_checkout_session.cart_id, create_checkout_session.protocol,
      create_checkout_session.idempotency_key, create_checkout_session.request_hash, create_checkout_session.expires_at)
    returning * into v_row;
  exception when unique_violation then
    select * into v_row from "better_supabase"."checkout_sessions" x
    where x."tenant_id" = create_checkout_session.tenant and x."idempotency_key" = create_checkout_session.idempotency_key;
    if not found or v_row."request_hash" <> create_checkout_session.request_hash then
      raise exception 'this idempotency key was used with another request' using errcode = '22023', hint = 'CHECKOUT_IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status", 'buyer', v_row."buyer", 'orderId', v_row."order_id", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" in ('open', 'ready') and v_row."expires_at" is not null and v_row."expires_at" <= now()), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('replayed', true);
  end;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status", 'buyer', v_row."buyer", 'orderId', v_row."order_id", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" in ('open', 'ready') and v_row."expires_at" is not null and v_row."expires_at" <= now()), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('replayed', false);
end;
$$;
revoke execute on function "better_supabase"."create_checkout_session"(uuid, uuid, text, text, text, timestamptz) from public, anon;
grant execute on function "better_supabase"."create_checkout_session"(uuid, uuid, text, text, text, timestamptz) to authenticated, service_role;

-- Changes an open session. input may hold buyer (a JSON object), status (open,
-- ready or canceled) and expiresAt. A completed or canceled session is final.
-- Needs agent_checkout.write.
create or replace function "better_supabase"."update_checkout_session"(session_id uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_input jsonb := coalesce(update_checkout_session.input, '{}'::jsonb);
  v_row "better_supabase"."checkout_sessions";
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."checkout_sessions" x where x."id" = update_checkout_session.session_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agent_checkout.read'), false))) then
    raise exception 'no such checkout session' using errcode = 'P0002', hint = 'CHECKOUT_SESSION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agent_checkout.write'), false))) then
    raise exception 'not allowed to change checkout sessions' using errcode = '42501', hint = 'CHECKOUT_FORBIDDEN';
  end if;
  if v_row."status" not in ('open', 'ready') then
    raise exception 'the session is completed or canceled' using errcode = '55000', hint = 'CHECKOUT_SESSION_FINAL';
  end if;
  if v_row."expires_at" is not null and v_row."expires_at" <= now() then
    raise exception 'the session expired' using errcode = '55000', hint = 'CHECKOUT_SESSION_EXPIRED';
  end if;
  v_status := coalesce(v_input ->> 'status', v_row."status");
  if v_status not in ('open', 'ready', 'canceled') then
    raise exception 'status is open, ready or canceled' using errcode = '22023', hint = 'CHECKOUT_INVALID';
  end if;
  if v_input ? 'buyer' and jsonb_typeof(v_input -> 'buyer') not in ('object', 'null') then
    raise exception 'buyer is an object or null' using errcode = '22023', hint = 'CHECKOUT_INVALID';
  end if;
  update "better_supabase"."checkout_sessions" x set
    "status" = v_status,
    "buyer" = case when v_input ? 'buyer' then nullif(v_input -> 'buyer', 'null'::jsonb) else x."buyer" end,
    "expires_at" = case when v_input ? 'expiresAt' then (v_input ->> 'expiresAt')::timestamptz else x."expires_at" end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status", 'buyer', v_row."buyer", 'orderId', v_row."order_id", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" in ('open', 'ready') and v_row."expires_at" is not null and v_row."expires_at" <= now()), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_checkout_session"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_checkout_session"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."get_checkout_session"(session_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."checkout_sessions";
begin
  select * into v_row from "better_supabase"."checkout_sessions" x where x."id" = get_checkout_session.session_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agent_checkout.read'), false))) then
    raise exception 'no such checkout session' using errcode = 'P0002', hint = 'CHECKOUT_SESSION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status", 'buyer', v_row."buyer", 'orderId', v_row."order_id", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" in ('open', 'ready') and v_row."expires_at" is not null and v_row."expires_at" <= now()), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."get_checkout_session"(uuid) from public, anon;
grant execute on function "better_supabase"."get_checkout_session"(uuid) to authenticated, service_role;

-- Sessions, newest first. filters is { status, protocol, cartId, limit, offset }.
create or replace function "better_supabase"."list_checkout_sessions"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_checkout_sessions.filters, '{}'::jsonb);
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_checkout_sessions.tenant is not null and coalesce(better_supabase.can('tenant', list_checkout_sessions.tenant, 'agent_checkout.read'), false))) then
    raise exception 'not allowed to read checkout sessions' using errcode = '42501', hint = 'CHECKOUT_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'cartId', y."cart_id", 'protocol', y."protocol", 'status', y."status", 'buyer', y."buyer", 'orderId', y."order_id", 'expiresAt', y."expires_at", 'expired', (y."status" in ('open', 'ready') and y."expires_at" is not null and y."expires_at" <= now()), 'createdBy', y."created_by", 'createdAt', y."created_at", 'updatedAt', y."updated_at") order by y."created_at" desc, y."id")
    from (
      select * from "better_supabase"."checkout_sessions" x
      where x."tenant_id" = list_checkout_sessions.tenant
        and (not v_filters ? 'status' or x."status" = v_filters ->> 'status')
        and (not v_filters ? 'protocol' or x."protocol" = v_filters ->> 'protocol')
        and (not v_filters ? 'cartId' or x."cart_id"::text = v_filters ->> 'cartId')
      order by x."created_at" desc, x."id"
      limit v_limit offset coalesce((v_filters ->> 'offset')::integer, 0)
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_checkout_sessions"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_checkout_sessions"(uuid, jsonb) to authenticated, service_role;

-- Marks a session completed with the order its cart became. Service only: the
-- TypeScript side calls it after the orders checkout placed the order and took
-- the payment through the payment provider. Completing again with the same
-- order returns the session.
create or replace function "better_supabase"."complete_checkout_session"(session_id uuid, order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."checkout_sessions";
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'only the service role completes checkout sessions' using errcode = '42501', hint = 'CHECKOUT_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."checkout_sessions" x where x."id" = complete_checkout_session.session_id for update;
  if not found then
    raise exception 'no such checkout session' using errcode = 'P0002', hint = 'CHECKOUT_SESSION_NOT_FOUND';
  end if;
  if v_row."status" = 'completed' then
    if v_row."order_id" = complete_checkout_session.order_id then
      return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status", 'buyer', v_row."buyer", 'orderId', v_row."order_id", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" in ('open', 'ready') and v_row."expires_at" is not null and v_row."expires_at" <= now()), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
    end if;
    raise exception 'the session completed with another order' using errcode = '55000', hint = 'CHECKOUT_SESSION_FINAL';
  end if;
  if v_row."status" = 'canceled' then
    raise exception 'the session is canceled' using errcode = '55000', hint = 'CHECKOUT_SESSION_FINAL';
  end if;
  if complete_checkout_session.order_id is null then
    raise exception 'order_id is required' using errcode = '22023', hint = 'CHECKOUT_INVALID';
  end if;
  update "better_supabase"."checkout_sessions" x set "status" = 'completed', "order_id" = complete_checkout_session.order_id, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status", 'buyer', v_row."buyer", 'orderId', v_row."order_id", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" in ('open', 'ready') and v_row."expires_at" is not null and v_row."expires_at" <= now()), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."complete_checkout_session"(uuid, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."complete_checkout_session"(uuid, uuid) to service_role;

-- Stores a verified mandate. input is { vct, credential, credentialHash,
-- issuerKid, subject, expiresAt, sessionId }. Storing the same credential
-- again returns the stored row. Needs agent_checkout.write.
create or replace function "better_supabase"."store_agent_mandate"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_input jsonb := coalesce(store_agent_mandate.input, '{}'::jsonb);
  v_row "better_supabase"."agent_mandates";
  v_expires timestamptz;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (store_agent_mandate.tenant is not null and coalesce(better_supabase.can('tenant', store_agent_mandate.tenant, 'agent_checkout.write'), false))) then
    raise exception 'not allowed to store mandates' using errcode = '42501', hint = 'AGENT_MANDATE_FORBIDDEN';
  end if;
  if coalesce(v_input ->> 'vct', '') not in ('mandate.checkout.open.1', 'mandate.checkout.1') then
    raise exception 'vct is mandate.checkout.open.1 or mandate.checkout.1' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
  end if;
  if coalesce(v_input ->> 'credential', '') = '' or coalesce(v_input ->> 'credentialHash', '') = '' or coalesce(v_input ->> 'expiresAt', '') = '' then
    raise exception 'a mandate needs a credential, its hash and an expiry' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
  end if;
  v_expires := (v_input ->> 'expiresAt')::timestamptz;
  if v_expires <= now() then
    raise exception 'the mandate expired' using errcode = '22023', hint = 'AGENT_MANDATE_EXPIRED';
  end if;
  if coalesce(v_input ->> 'sessionId', '') <> '' and not exists (
    select 1 from "better_supabase"."checkout_sessions" x
    where x."id" = (v_input ->> 'sessionId')::uuid and x."tenant_id" = store_agent_mandate.tenant
  ) then
    raise exception 'no such checkout session' using errcode = 'P0002', hint = 'CHECKOUT_SESSION_NOT_FOUND';
  end if;
  insert into "better_supabase"."agent_mandates" ("tenant_id", "session_id", "vct", "credential", "credential_hash", "issuer_kid", "subject", "expires_at")
  values (store_agent_mandate.tenant, nullif(v_input ->> 'sessionId', '')::uuid, v_input ->> 'vct', v_input ->> 'credential',
    v_input ->> 'credentialHash', nullif(v_input ->> 'issuerKid', ''), nullif(v_input ->> 'subject', ''), v_expires)
  on conflict ("tenant_id", "credential_hash") do nothing
  returning * into v_row;
  if not found then
    select * into v_row from "better_supabase"."agent_mandates" x
    where x."tenant_id" = store_agent_mandate.tenant and x."credential_hash" = v_input ->> 'credentialHash';
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'sessionId', v_row."session_id", 'vct', v_row."vct", 'status', v_row."status", 'credential', v_row."credential", 'credentialHash', v_row."credential_hash", 'issuerKid', v_row."issuer_kid", 'subject', v_row."subject", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" = 'active' and v_row."expires_at" <= now()), 'consumedAt', v_row."consumed_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
  end if;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'sessionId', v_row."session_id", 'vct', v_row."vct", 'status', v_row."status", 'credential', v_row."credential", 'credentialHash', v_row."credential_hash", 'issuerKid', v_row."issuer_kid", 'subject', v_row."subject", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" = 'active' and v_row."expires_at" <= now()), 'consumedAt', v_row."consumed_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."store_agent_mandate"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."store_agent_mandate"(uuid, jsonb) to authenticated, service_role;

-- Uses a closed mandate once, for one session. An open mandate is never
-- consumed: it keeps authorizing closed ones until it expires or is revoked.
-- Needs agent_checkout.write.
create or replace function "better_supabase"."consume_agent_mandate"(mandate_id uuid, session_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."agent_mandates";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."agent_mandates" x where x."id" = consume_agent_mandate.mandate_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agent_checkout.read'), false))) then
    raise exception 'no such mandate' using errcode = 'P0002', hint = 'AGENT_MANDATE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agent_checkout.write'), false))) then
    raise exception 'not allowed to use mandates' using errcode = '42501', hint = 'AGENT_MANDATE_FORBIDDEN';
  end if;
  if v_row."vct" <> 'mandate.checkout.1' then
    raise exception 'only a closed mandate is consumed' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
  end if;
  if v_row."status" <> 'active' then
    raise exception 'the mandate was already used or revoked' using errcode = '55000', hint = 'AGENT_MANDATE_USED';
  end if;
  if v_row."expires_at" <= now() then
    raise exception 'the mandate expired' using errcode = '55000', hint = 'AGENT_MANDATE_EXPIRED';
  end if;
  if v_row."session_id" is not null and v_row."session_id" <> consume_agent_mandate.session_id then
    raise exception 'the mandate belongs to another session' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
  end if;
  update "better_supabase"."agent_mandates" x set "status" = 'consumed', "consumed_at" = now(), "session_id" = coalesce(x."session_id", consume_agent_mandate.session_id)
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'sessionId', v_row."session_id", 'vct', v_row."vct", 'status', v_row."status", 'credential', v_row."credential", 'credentialHash', v_row."credential_hash", 'issuerKid', v_row."issuer_kid", 'subject', v_row."subject", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" = 'active' and v_row."expires_at" <= now()), 'consumedAt', v_row."consumed_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."consume_agent_mandate"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."consume_agent_mandate"(uuid, uuid) to authenticated, service_role;

-- Revokes an active mandate; false when it was not active. Needs
-- agent_checkout.manage.
create or replace function "better_supabase"."revoke_agent_mandate"(mandate_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."agent_mandates";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."agent_mandates" x where x."id" = revoke_agent_mandate.mandate_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agent_checkout.read'), false))) then
    raise exception 'no such mandate' using errcode = 'P0002', hint = 'AGENT_MANDATE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agent_checkout.manage'), false))) then
    raise exception 'not allowed to revoke mandates' using errcode = '42501', hint = 'AGENT_MANDATE_FORBIDDEN';
  end if;
  if v_row."status" <> 'active' then
    return false;
  end if;
  update "better_supabase"."agent_mandates" x set "status" = 'revoked' where x."id" = v_row."id" returning * into v_row;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."revoke_agent_mandate"(uuid) from public, anon;
grant execute on function "better_supabase"."revoke_agent_mandate"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."get_agent_mandate"(mandate_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."agent_mandates";
begin
  select * into v_row from "better_supabase"."agent_mandates" x where x."id" = get_agent_mandate.mandate_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agent_checkout.read'), false))) then
    raise exception 'no such mandate' using errcode = 'P0002', hint = 'AGENT_MANDATE_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'sessionId', v_row."session_id", 'vct', v_row."vct", 'status', v_row."status", 'credential', v_row."credential", 'credentialHash', v_row."credential_hash", 'issuerKid', v_row."issuer_kid", 'subject', v_row."subject", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" = 'active' and v_row."expires_at" <= now()), 'consumedAt', v_row."consumed_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."get_agent_mandate"(uuid) from public, anon;
grant execute on function "better_supabase"."get_agent_mandate"(uuid) to authenticated, service_role;

-- Mandates, newest first. filters is { sessionId, status, vct, limit, offset }.
create or replace function "better_supabase"."list_agent_mandates"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_agent_mandates.filters, '{}'::jsonb);
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_agent_mandates.tenant is not null and coalesce(better_supabase.can('tenant', list_agent_mandates.tenant, 'agent_checkout.read'), false))) then
    raise exception 'not allowed to read mandates' using errcode = '42501', hint = 'AGENT_MANDATE_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'sessionId', y."session_id", 'vct', y."vct", 'status', y."status", 'credential', y."credential", 'credentialHash', y."credential_hash", 'issuerKid', y."issuer_kid", 'subject', y."subject", 'expiresAt', y."expires_at", 'expired', (y."status" = 'active' and y."expires_at" <= now()), 'consumedAt', y."consumed_at", 'createdBy', y."created_by", 'createdAt', y."created_at") order by y."created_at" desc, y."id")
    from (
      select * from "better_supabase"."agent_mandates" x
      where x."tenant_id" = list_agent_mandates.tenant
        and (not v_filters ? 'sessionId' or x."session_id"::text = v_filters ->> 'sessionId')
        and (not v_filters ? 'status' or x."status" = v_filters ->> 'status')
        and (not v_filters ? 'vct' or x."vct" = v_filters ->> 'vct')
      order by x."created_at" desc, x."id"
      limit v_limit offset coalesce((v_filters ->> 'offset')::integer, 0)
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_agent_mandates"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_agent_mandates"(uuid, jsonb) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."checkout_sessions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."checkout_sessions";
create policy bsb_tenant_scope_select on "better_supabase"."checkout_sessions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('agent_checkout.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."checkout_sessions";
create policy bsb_tenant_scope_insert on "better_supabase"."checkout_sessions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."checkout_sessions";
create policy bsb_tenant_scope_update on "better_supabase"."checkout_sessions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."checkout_sessions";
create policy bsb_tenant_scope_delete on "better_supabase"."checkout_sessions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."agent_mandates";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."agent_mandates";
create policy bsb_tenant_scope_select on "better_supabase"."agent_mandates" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('agent_checkout.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."agent_mandates";
create policy bsb_tenant_scope_insert on "better_supabase"."agent_mandates" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."agent_mandates";
create policy bsb_tenant_scope_update on "better_supabase"."agent_mandates" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."agent_mandates";
create policy bsb_tenant_scope_delete on "better_supabase"."agent_mandates" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

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
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_171_agent_checkout.sql
-- better-supabase module: agent-checkout
-- @bsb-block-data agent-checkout
-- @bsb-hash sha256:f2ff7f54e754107be5e7c58c415111abecc80d24eacb7640b39ab53ea8c96238
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('agent-checkout', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_171_agent_checkout.sql
-- better-supabase module: agent-checkout
-- @bsb-block agent-checkout@1 managed
-- @bsb-hash sha256:957f6c56a586664d7184904b96d7c2d8b8d1d4661d72f20facdc646ebecc7d6e
-- ACP and UCP checkout sessions over an orders cart with idempotency keys, and AP2 checkout mandates verified with signing keys and used once.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."checkout_sessions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."checkout_sessions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."checkout_sessions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."checkout_sessions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."checkout_sessions";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."agent_mandates";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."agent_mandates";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."agent_mandates";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."agent_mandates";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."agent_mandates";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Agent checkout: ACP and UCP checkout sessions over an orders cart, and AP2
-- mandates stored beside them. The session keeps the protocol state; the cart
-- and the order keep the money (bigint minor units).
create table if not exists "better_supabase"."checkout_sessions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "cart_id" uuid not null,
  "protocol" text not null check ("protocol" in ('acp', 'ucp')),
  "status" text not null default 'open' check ("status" in ('open', 'ready', 'completed', 'canceled')),
  "idempotency_key" text not null check (length("idempotency_key") between 1 and 255),
  "request_hash" text not null check (length("request_hash") between 1 and 128),
  "buyer" jsonb,
  "order_id" uuid,
  "expires_at" timestamptz,
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "idempotency_key"),
  check (("status" = 'completed') = ("order_id" is not null))
);
create index if not exists "checkout_sessions_cart_idx" on "better_supabase"."checkout_sessions" ("cart_id");
alter table "better_supabase"."checkout_sessions" enable row level security;
revoke all on "better_supabase"."checkout_sessions" from public, anon, authenticated;
grant select on "better_supabase"."checkout_sessions" to authenticated;
grant all on "better_supabase"."checkout_sessions" to service_role;
drop policy if exists checkout_sessions_read on "better_supabase"."checkout_sessions";
create policy checkout_sessions_read on "better_supabase"."checkout_sessions"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('agent_checkout.read')));

-- A mandate an agent presents: the compact credential, its hash and the key
-- that signed it. The TypeScript side verifies the signature with the
-- signing-keys block before it stores the row; closed mandates are used once.
create table if not exists "better_supabase"."agent_mandates" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "session_id" uuid references "better_supabase"."checkout_sessions" ("id") on delete set null,
  "vct" text not null check ("vct" in ('mandate.checkout.open.1', 'mandate.checkout.1')),
  "status" text not null default 'active' check ("status" in ('active', 'consumed', 'revoked')),
  "credential" text not null check (length("credential") between 1 and 16384),
  "credential_hash" text not null check (length("credential_hash") between 1 and 128),
  "issuer_kid" text,
  "subject" text,
  "expires_at" timestamptz not null,
  "consumed_at" timestamptz,
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "credential_hash"),
  check (("status" = 'consumed') = ("consumed_at" is not null))
);
create index if not exists "agent_mandates_session_idx" on "better_supabase"."agent_mandates" ("session_id");
alter table "better_supabase"."agent_mandates" enable row level security;
revoke all on "better_supabase"."agent_mandates" from public, anon, authenticated;
grant select on "better_supabase"."agent_mandates" to authenticated;
grant all on "better_supabase"."agent_mandates" to service_role;
drop policy if exists agent_mandates_read on "better_supabase"."agent_mandates";
create policy agent_mandates_read on "better_supabase"."agent_mandates"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('agent_checkout.read')));

-- Starts a checkout session over a cart, or returns the one this idempotency
-- key made before (replayed true). The same key with another request_hash
-- fails with CHECKOUT_IDEMPOTENCY_CONFLICT. Needs agent_checkout.write.
create or replace function "better_supabase"."create_checkout_session"(tenant uuid, cart_id uuid, protocol text, idempotency_key text, request_hash text, expires_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."checkout_sessions";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_checkout_session.tenant is not null and coalesce(better_supabase.can('tenant', create_checkout_session.tenant, 'agent_checkout.write'), false))) then
    raise exception 'not allowed to start checkout sessions' using errcode = '42501', hint = 'CHECKOUT_FORBIDDEN';
  end if;
  if create_checkout_session.protocol is null or create_checkout_session.protocol not in ('acp', 'ucp') then
    raise exception 'the protocol is acp or ucp' using errcode = '22023', hint = 'CHECKOUT_INVALID';
  end if;
  if coalesce(create_checkout_session.idempotency_key, '') = '' or coalesce(create_checkout_session.request_hash, '') = '' then
    raise exception 'a checkout session needs an idempotency key' using errcode = '22023', hint = 'CHECKOUT_IDEMPOTENCY_KEY_REQUIRED';
  end if;
  select * into v_row from "better_supabase"."checkout_sessions" x
  where x."tenant_id" = create_checkout_session.tenant and x."idempotency_key" = create_checkout_session.idempotency_key;
  if found then
    if v_row."request_hash" <> create_checkout_session.request_hash then
      raise exception 'this idempotency key was used with another request' using errcode = '22023', hint = 'CHECKOUT_IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status", 'buyer', v_row."buyer", 'orderId', v_row."order_id", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" in ('open', 'ready') and v_row."expires_at" is not null and v_row."expires_at" <= now()), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('replayed', true);
  end if;
  if not exists (
    select 1 from "better_supabase"."carts" c
    where c."id" = create_checkout_session.cart_id
      and c."tenant_id" = create_checkout_session.tenant
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or c."user_id" = auth.uid())
  ) then
    raise exception 'no such cart' using errcode = 'P0002', hint = 'CHECKOUT_CART_NOT_FOUND';
  end if;
  begin
    insert into "better_supabase"."checkout_sessions" ("tenant_id", "cart_id", "protocol", "idempotency_key", "request_hash", "expires_at")
    values (create_checkout_session.tenant, create_checkout_session.cart_id, create_checkout_session.protocol,
      create_checkout_session.idempotency_key, create_checkout_session.request_hash, create_checkout_session.expires_at)
    returning * into v_row;
  exception when unique_violation then
    select * into v_row from "better_supabase"."checkout_sessions" x
    where x."tenant_id" = create_checkout_session.tenant and x."idempotency_key" = create_checkout_session.idempotency_key;
    if not found or v_row."request_hash" <> create_checkout_session.request_hash then
      raise exception 'this idempotency key was used with another request' using errcode = '22023', hint = 'CHECKOUT_IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status", 'buyer', v_row."buyer", 'orderId', v_row."order_id", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" in ('open', 'ready') and v_row."expires_at" is not null and v_row."expires_at" <= now()), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('replayed', true);
  end;
  perform "better_supabase".emit_event('checkout_session.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status"), 'checkout-sessions/' || v_row."id"::text, (v_row."tenant_id")::text, 'checkout_session.created:' || v_row."id"::text || ':' || v_row."status", 'better-supabase/agent-checkout');
  perform better_supabase.audit_event(
    event_type => 'checkout_session.created',
    category => 'data',
    target_type => 'checkout_session',
    record_id => v_row."id"::text,
    summary => 'checkout session created',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status"),
    idempotency_key => 'checkout_session.created:' || v_row."id"::text || ':' || v_row."status"
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status", 'buyer', v_row."buyer", 'orderId', v_row."order_id", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" in ('open', 'ready') and v_row."expires_at" is not null and v_row."expires_at" <= now()), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('replayed', false);
end;
$$;
revoke execute on function "better_supabase"."create_checkout_session"(uuid, uuid, text, text, text, timestamptz) from public, anon;
grant execute on function "better_supabase"."create_checkout_session"(uuid, uuid, text, text, text, timestamptz) to authenticated, service_role;

-- Changes an open session. input may hold buyer (a JSON object), status (open,
-- ready or canceled) and expiresAt. A completed or canceled session is final.
-- Needs agent_checkout.write.
create or replace function "better_supabase"."update_checkout_session"(session_id uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_input jsonb := coalesce(update_checkout_session.input, '{}'::jsonb);
  v_row "better_supabase"."checkout_sessions";
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."checkout_sessions" x where x."id" = update_checkout_session.session_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agent_checkout.read'), false))) then
    raise exception 'no such checkout session' using errcode = 'P0002', hint = 'CHECKOUT_SESSION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agent_checkout.write'), false))) then
    raise exception 'not allowed to change checkout sessions' using errcode = '42501', hint = 'CHECKOUT_FORBIDDEN';
  end if;
  if v_row."status" not in ('open', 'ready') then
    raise exception 'the session is completed or canceled' using errcode = '55000', hint = 'CHECKOUT_SESSION_FINAL';
  end if;
  if v_row."expires_at" is not null and v_row."expires_at" <= now() then
    raise exception 'the session expired' using errcode = '55000', hint = 'CHECKOUT_SESSION_EXPIRED';
  end if;
  v_status := coalesce(v_input ->> 'status', v_row."status");
  if v_status not in ('open', 'ready', 'canceled') then
    raise exception 'status is open, ready or canceled' using errcode = '22023', hint = 'CHECKOUT_INVALID';
  end if;
  if v_input ? 'buyer' and jsonb_typeof(v_input -> 'buyer') not in ('object', 'null') then
    raise exception 'buyer is an object or null' using errcode = '22023', hint = 'CHECKOUT_INVALID';
  end if;
  update "better_supabase"."checkout_sessions" x set
    "status" = v_status,
    "buyer" = case when v_input ? 'buyer' then nullif(v_input -> 'buyer', 'null'::jsonb) else x."buyer" end,
    "expires_at" = case when v_input ? 'expiresAt' then (v_input ->> 'expiresAt')::timestamptz else x."expires_at" end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('checkout_session.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status"), 'checkout-sessions/' || v_row."id"::text, (v_row."tenant_id")::text, 'checkout_session.updated:' || v_row."id"::text || ':' || v_row."status", 'better-supabase/agent-checkout');
  perform better_supabase.audit_event(
    event_type => 'checkout_session.updated',
    category => 'data',
    target_type => 'checkout_session',
    record_id => v_row."id"::text,
    summary => 'checkout session changed',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status"),
    idempotency_key => 'checkout_session.updated:' || v_row."id"::text || ':' || v_row."status"
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status", 'buyer', v_row."buyer", 'orderId', v_row."order_id", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" in ('open', 'ready') and v_row."expires_at" is not null and v_row."expires_at" <= now()), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_checkout_session"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_checkout_session"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."get_checkout_session"(session_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."checkout_sessions";
begin
  select * into v_row from "better_supabase"."checkout_sessions" x where x."id" = get_checkout_session.session_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agent_checkout.read'), false))) then
    raise exception 'no such checkout session' using errcode = 'P0002', hint = 'CHECKOUT_SESSION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status", 'buyer', v_row."buyer", 'orderId', v_row."order_id", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" in ('open', 'ready') and v_row."expires_at" is not null and v_row."expires_at" <= now()), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."get_checkout_session"(uuid) from public, anon;
grant execute on function "better_supabase"."get_checkout_session"(uuid) to authenticated, service_role;

-- Sessions, newest first. filters is { status, protocol, cartId, limit, offset }.
create or replace function "better_supabase"."list_checkout_sessions"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_checkout_sessions.filters, '{}'::jsonb);
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_checkout_sessions.tenant is not null and coalesce(better_supabase.can('tenant', list_checkout_sessions.tenant, 'agent_checkout.read'), false))) then
    raise exception 'not allowed to read checkout sessions' using errcode = '42501', hint = 'CHECKOUT_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'cartId', y."cart_id", 'protocol', y."protocol", 'status', y."status", 'buyer', y."buyer", 'orderId', y."order_id", 'expiresAt', y."expires_at", 'expired', (y."status" in ('open', 'ready') and y."expires_at" is not null and y."expires_at" <= now()), 'createdBy', y."created_by", 'createdAt', y."created_at", 'updatedAt', y."updated_at") order by y."created_at" desc, y."id")
    from (
      select * from "better_supabase"."checkout_sessions" x
      where x."tenant_id" = list_checkout_sessions.tenant
        and (not v_filters ? 'status' or x."status" = v_filters ->> 'status')
        and (not v_filters ? 'protocol' or x."protocol" = v_filters ->> 'protocol')
        and (not v_filters ? 'cartId' or x."cart_id"::text = v_filters ->> 'cartId')
      order by x."created_at" desc, x."id"
      limit v_limit offset coalesce((v_filters ->> 'offset')::integer, 0)
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_checkout_sessions"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_checkout_sessions"(uuid, jsonb) to authenticated, service_role;

-- Marks a session completed with the order its cart became. Service only: the
-- TypeScript side calls it after the orders checkout placed the order and took
-- the payment through the payment provider. Completing again with the same
-- order returns the session.
create or replace function "better_supabase"."complete_checkout_session"(session_id uuid, order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."checkout_sessions";
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'only the service role completes checkout sessions' using errcode = '42501', hint = 'CHECKOUT_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."checkout_sessions" x where x."id" = complete_checkout_session.session_id for update;
  if not found then
    raise exception 'no such checkout session' using errcode = 'P0002', hint = 'CHECKOUT_SESSION_NOT_FOUND';
  end if;
  if v_row."status" = 'completed' then
    if v_row."order_id" = complete_checkout_session.order_id then
      return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status", 'buyer', v_row."buyer", 'orderId', v_row."order_id", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" in ('open', 'ready') and v_row."expires_at" is not null and v_row."expires_at" <= now()), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
    end if;
    raise exception 'the session completed with another order' using errcode = '55000', hint = 'CHECKOUT_SESSION_FINAL';
  end if;
  if v_row."status" = 'canceled' then
    raise exception 'the session is canceled' using errcode = '55000', hint = 'CHECKOUT_SESSION_FINAL';
  end if;
  if complete_checkout_session.order_id is null then
    raise exception 'order_id is required' using errcode = '22023', hint = 'CHECKOUT_INVALID';
  end if;
  if not exists (
    select 1 from "better_supabase"."orders" o
    where o."id" = complete_checkout_session.order_id
      and o."cart_id" = v_row."cart_id"
      and o."tenant_id" = v_row."tenant_id"
  ) then
    raise exception 'the order is not the one placed from the session''s cart' using errcode = '22023', hint = 'CHECKOUT_INVALID';
  end if;
  update "better_supabase"."checkout_sessions" x set "status" = 'completed', "order_id" = complete_checkout_session.order_id, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('checkout_session.completed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status", 'orderId', v_row."order_id"), 'checkout-sessions/' || v_row."id"::text, (v_row."tenant_id")::text, 'checkout_session.completed:' || v_row."id"::text || ':' || v_row."status", 'better-supabase/agent-checkout');
  perform better_supabase.audit_event(
    event_type => 'checkout_session.completed',
    category => 'data',
    target_type => 'checkout_session',
    record_id => v_row."id"::text,
    summary => 'checkout session completed',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status", 'orderId', v_row."order_id"),
    idempotency_key => 'checkout_session.completed:' || v_row."id"::text || ':' || v_row."status"
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status", 'buyer', v_row."buyer", 'orderId', v_row."order_id", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" in ('open', 'ready') and v_row."expires_at" is not null and v_row."expires_at" <= now()), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."complete_checkout_session"(uuid, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."complete_checkout_session"(uuid, uuid) to service_role;

-- Stores a verified mandate. input is { vct, credential, credentialHash,
-- issuerKid, subject, expiresAt, sessionId }. Storing the same credential
-- again returns the stored row. Needs agent_checkout.write.
create or replace function "better_supabase"."store_agent_mandate"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_input jsonb := coalesce(store_agent_mandate.input, '{}'::jsonb);
  v_row "better_supabase"."agent_mandates";
  v_expires timestamptz;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (store_agent_mandate.tenant is not null and coalesce(better_supabase.can('tenant', store_agent_mandate.tenant, 'agent_checkout.write'), false))) then
    raise exception 'not allowed to store mandates' using errcode = '42501', hint = 'AGENT_MANDATE_FORBIDDEN';
  end if;
  if coalesce(v_input ->> 'vct', '') not in ('mandate.checkout.open.1', 'mandate.checkout.1') then
    raise exception 'vct is mandate.checkout.open.1 or mandate.checkout.1' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
  end if;
  if coalesce(v_input ->> 'credential', '') = '' or coalesce(v_input ->> 'credentialHash', '') = '' or coalesce(v_input ->> 'expiresAt', '') = '' then
    raise exception 'a mandate needs a credential, its hash and an expiry' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
  end if;
  v_expires := (v_input ->> 'expiresAt')::timestamptz;
  if v_expires <= now() then
    raise exception 'the mandate expired' using errcode = '22023', hint = 'AGENT_MANDATE_EXPIRED';
  end if;
  if coalesce(v_input ->> 'sessionId', '') <> '' and not exists (
    select 1 from "better_supabase"."checkout_sessions" x
    where x."id" = (v_input ->> 'sessionId')::uuid and x."tenant_id" = store_agent_mandate.tenant
  ) then
    raise exception 'no such checkout session' using errcode = 'P0002', hint = 'CHECKOUT_SESSION_NOT_FOUND';
  end if;
  insert into "better_supabase"."agent_mandates" ("tenant_id", "session_id", "vct", "credential", "credential_hash", "issuer_kid", "subject", "expires_at")
  values (store_agent_mandate.tenant, nullif(v_input ->> 'sessionId', '')::uuid, v_input ->> 'vct', v_input ->> 'credential',
    v_input ->> 'credentialHash', nullif(v_input ->> 'issuerKid', ''), nullif(v_input ->> 'subject', ''), v_expires)
  on conflict ("tenant_id", "credential_hash") do nothing
  returning * into v_row;
  if not found then
    select * into v_row from "better_supabase"."agent_mandates" x
    where x."tenant_id" = store_agent_mandate.tenant and x."credential_hash" = v_input ->> 'credentialHash';
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'sessionId', v_row."session_id", 'vct', v_row."vct", 'status', v_row."status", 'credential', v_row."credential", 'credentialHash', v_row."credential_hash", 'issuerKid', v_row."issuer_kid", 'subject', v_row."subject", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" = 'active' and v_row."expires_at" <= now()), 'consumedAt', v_row."consumed_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
  end if;
  perform "better_supabase".emit_event('agent_mandate.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'vct', v_row."vct", 'sessionId', v_row."session_id"), 'agent-mandates/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/agent-checkout');
  perform better_supabase.audit_event(
    event_type => 'agent_mandate.created',
    category => 'security',
    target_type => 'agent_mandate',
    record_id => v_row."id"::text,
    summary => 'agent mandate stored',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'vct', v_row."vct", 'sessionId', v_row."session_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'sessionId', v_row."session_id", 'vct', v_row."vct", 'status', v_row."status", 'credential', v_row."credential", 'credentialHash', v_row."credential_hash", 'issuerKid', v_row."issuer_kid", 'subject', v_row."subject", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" = 'active' and v_row."expires_at" <= now()), 'consumedAt', v_row."consumed_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."store_agent_mandate"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."store_agent_mandate"(uuid, jsonb) to authenticated, service_role;

-- Uses a closed mandate once, for one session. An open mandate is never
-- consumed: it keeps authorizing closed ones until it expires or is revoked.
-- Needs agent_checkout.write.
create or replace function "better_supabase"."consume_agent_mandate"(mandate_id uuid, session_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."agent_mandates";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."agent_mandates" x where x."id" = consume_agent_mandate.mandate_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agent_checkout.read'), false))) then
    raise exception 'no such mandate' using errcode = 'P0002', hint = 'AGENT_MANDATE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agent_checkout.write'), false))) then
    raise exception 'not allowed to use mandates' using errcode = '42501', hint = 'AGENT_MANDATE_FORBIDDEN';
  end if;
  if v_row."vct" <> 'mandate.checkout.1' then
    raise exception 'only a closed mandate is consumed' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
  end if;
  if v_row."status" <> 'active' then
    raise exception 'the mandate was already used or revoked' using errcode = '55000', hint = 'AGENT_MANDATE_USED';
  end if;
  if v_row."expires_at" <= now() then
    raise exception 'the mandate expired' using errcode = '55000', hint = 'AGENT_MANDATE_EXPIRED';
  end if;
  if v_row."session_id" is not null and v_row."session_id" <> consume_agent_mandate.session_id then
    raise exception 'the mandate belongs to another session' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
  end if;
  update "better_supabase"."agent_mandates" x set "status" = 'consumed', "consumed_at" = now(), "session_id" = coalesce(x."session_id", consume_agent_mandate.session_id)
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('agent_mandate.consumed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'vct', v_row."vct", 'sessionId', v_row."session_id"), 'agent-mandates/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/agent-checkout');
  perform better_supabase.audit_event(
    event_type => 'agent_mandate.consumed',
    category => 'security',
    target_type => 'agent_mandate',
    record_id => v_row."id"::text,
    summary => 'agent mandate used',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'vct', v_row."vct", 'sessionId', v_row."session_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'sessionId', v_row."session_id", 'vct', v_row."vct", 'status', v_row."status", 'credential', v_row."credential", 'credentialHash', v_row."credential_hash", 'issuerKid', v_row."issuer_kid", 'subject', v_row."subject", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" = 'active' and v_row."expires_at" <= now()), 'consumedAt', v_row."consumed_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."consume_agent_mandate"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."consume_agent_mandate"(uuid, uuid) to authenticated, service_role;

-- Revokes an active mandate; false when it was not active. Needs
-- agent_checkout.manage.
create or replace function "better_supabase"."revoke_agent_mandate"(mandate_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."agent_mandates";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."agent_mandates" x where x."id" = revoke_agent_mandate.mandate_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agent_checkout.read'), false))) then
    raise exception 'no such mandate' using errcode = 'P0002', hint = 'AGENT_MANDATE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agent_checkout.manage'), false))) then
    raise exception 'not allowed to revoke mandates' using errcode = '42501', hint = 'AGENT_MANDATE_FORBIDDEN';
  end if;
  if v_row."status" <> 'active' then
    return false;
  end if;
  update "better_supabase"."agent_mandates" x set "status" = 'revoked' where x."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('agent_mandate.revoked', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'vct', v_row."vct", 'sessionId', v_row."session_id"), 'agent-mandates/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/agent-checkout');
  perform better_supabase.audit_event(
    event_type => 'agent_mandate.revoked',
    category => 'security',
    target_type => 'agent_mandate',
    record_id => v_row."id"::text,
    summary => 'agent mandate revoked',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'vct', v_row."vct", 'sessionId', v_row."session_id")
  );
  return true;
end;
$$;
revoke execute on function "better_supabase"."revoke_agent_mandate"(uuid) from public, anon;
grant execute on function "better_supabase"."revoke_agent_mandate"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."get_agent_mandate"(mandate_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."agent_mandates";
begin
  select * into v_row from "better_supabase"."agent_mandates" x where x."id" = get_agent_mandate.mandate_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agent_checkout.read'), false))) then
    raise exception 'no such mandate' using errcode = 'P0002', hint = 'AGENT_MANDATE_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'sessionId', v_row."session_id", 'vct', v_row."vct", 'status', v_row."status", 'credential', v_row."credential", 'credentialHash', v_row."credential_hash", 'issuerKid', v_row."issuer_kid", 'subject', v_row."subject", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" = 'active' and v_row."expires_at" <= now()), 'consumedAt', v_row."consumed_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."get_agent_mandate"(uuid) from public, anon;
grant execute on function "better_supabase"."get_agent_mandate"(uuid) to authenticated, service_role;

-- Mandates, newest first. filters is { sessionId, status, vct, limit, offset }.
create or replace function "better_supabase"."list_agent_mandates"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_agent_mandates.filters, '{}'::jsonb);
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_agent_mandates.tenant is not null and coalesce(better_supabase.can('tenant', list_agent_mandates.tenant, 'agent_checkout.read'), false))) then
    raise exception 'not allowed to read mandates' using errcode = '42501', hint = 'AGENT_MANDATE_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'sessionId', y."session_id", 'vct', y."vct", 'status', y."status", 'credential', y."credential", 'credentialHash', y."credential_hash", 'issuerKid', y."issuer_kid", 'subject', y."subject", 'expiresAt', y."expires_at", 'expired', (y."status" = 'active' and y."expires_at" <= now()), 'consumedAt', y."consumed_at", 'createdBy', y."created_by", 'createdAt', y."created_at") order by y."created_at" desc, y."id")
    from (
      select * from "better_supabase"."agent_mandates" x
      where x."tenant_id" = list_agent_mandates.tenant
        and (not v_filters ? 'sessionId' or x."session_id"::text = v_filters ->> 'sessionId')
        and (not v_filters ? 'status' or x."status" = v_filters ->> 'status')
        and (not v_filters ? 'vct' or x."vct" = v_filters ->> 'vct')
      order by x."created_at" desc, x."id"
      limit v_limit offset coalesce((v_filters ->> 'offset')::integer, 0)
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_agent_mandates"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_agent_mandates"(uuid, jsonb) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."checkout_sessions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."checkout_sessions";
create policy bsb_tenant_scope_select on "better_supabase"."checkout_sessions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('agent_checkout.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."checkout_sessions";
create policy bsb_tenant_scope_insert on "better_supabase"."checkout_sessions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."checkout_sessions";
create policy bsb_tenant_scope_update on "better_supabase"."checkout_sessions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."checkout_sessions";
create policy bsb_tenant_scope_delete on "better_supabase"."checkout_sessions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."agent_mandates";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."agent_mandates";
create policy bsb_tenant_scope_select on "better_supabase"."agent_mandates" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('agent_checkout.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."agent_mandates";
create policy bsb_tenant_scope_insert on "better_supabase"."agent_mandates" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."agent_mandates";
create policy bsb_tenant_scope_update on "better_supabase"."agent_mandates" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."agent_mandates";
create policy bsb_tenant_scope_delete on "better_supabase"."agent_mandates" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- Row audit for the module's tables (blocks.audit.options.blockTables)
do $$
begin
  perform better_supabase.audit('better_supabase.checkout_sessions', target_type => 'checkout_session', event_prefix => 'checkout_session', deferred => true);
  perform better_supabase.audit('better_supabase.agent_mandates', target_type => 'agent_mandate', event_prefix => 'agent_mandate', deferred => true);
end;
$$;

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
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_171_agent_checkout.sql
-- better-supabase module: agent-checkout
-- @bsb-block-data agent-checkout
-- @bsb-hash sha256:f2ff7f54e754107be5e7c58c415111abecc80d24eacb7640b39ab53ea8c96238
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('agent-checkout', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_171_agent_checkout.sql
-- better-supabase module: agent-checkout
-- @bsb-block agent-checkout@1 managed
-- @bsb-hash sha256:97dd2c4176816291bb3a38290eca23957e003287940e0afd669b744fe1bc0afa
-- ACP and UCP checkout sessions over an orders cart with idempotency keys, and AP2 checkout mandates verified with signing keys and used once.
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
    drop policy if exists bsb_tenant_scope on "app_private"."checkout_sessions";
    drop policy if exists bsb_tenant_scope_select on "app_private"."checkout_sessions";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."checkout_sessions";
    drop policy if exists bsb_tenant_scope_update on "app_private"."checkout_sessions";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."checkout_sessions";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."agent_mandates";
    drop policy if exists bsb_tenant_scope_select on "app_private"."agent_mandates";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."agent_mandates";
    drop policy if exists bsb_tenant_scope_update on "app_private"."agent_mandates";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."agent_mandates";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;
-- Agent checkout: ACP and UCP checkout sessions over an orders cart, and AP2
-- mandates stored beside them. The session keeps the protocol state; the cart
-- and the order keep the money (bigint minor units).
create table if not exists "app_private"."checkout_sessions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "cart_id" uuid not null,
  "protocol" text not null check ("protocol" in ('acp', 'ucp')),
  "status" text not null default 'open' check ("status" in ('open', 'ready', 'completed', 'canceled')),
  "idempotency_key" text not null check (length("idempotency_key") between 1 and 255),
  "request_hash" text not null check (length("request_hash") between 1 and 128),
  "buyer" jsonb,
  "order_id" uuid,
  "expires_at" timestamptz,
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "idempotency_key"),
  check (("status" = 'completed') = ("order_id" is not null))
);
create index if not exists "checkout_sessions_cart_idx" on "app_private"."checkout_sessions" ("cart_id");
alter table "app_private"."checkout_sessions" enable row level security;
revoke all on "app_private"."checkout_sessions" from public, anon, authenticated;
grant select on "app_private"."checkout_sessions" to authenticated;
grant all on "app_private"."checkout_sessions" to service_role;
drop policy if exists checkout_sessions_read on "app_private"."checkout_sessions";
create policy checkout_sessions_read on "app_private"."checkout_sessions"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('agent_checkout.read')));

-- A mandate an agent presents: the compact credential, its hash and the key
-- that signed it. The TypeScript side verifies the signature with the
-- signing-keys block before it stores the row; closed mandates are used once.
create table if not exists "app_private"."agent_mandates" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "session_id" uuid references "app_private"."checkout_sessions" ("id") on delete set null,
  "vct" text not null check ("vct" in ('mandate.checkout.open.1', 'mandate.checkout.1')),
  "status" text not null default 'active' check ("status" in ('active', 'consumed', 'revoked')),
  "credential" text not null check (length("credential") between 1 and 16384),
  "credential_hash" text not null check (length("credential_hash") between 1 and 128),
  "issuer_kid" text,
  "subject" text,
  "expires_at" timestamptz not null,
  "consumed_at" timestamptz,
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "credential_hash"),
  check (("status" = 'consumed') = ("consumed_at" is not null))
);
create index if not exists "agent_mandates_session_idx" on "app_private"."agent_mandates" ("session_id");
alter table "app_private"."agent_mandates" enable row level security;
revoke all on "app_private"."agent_mandates" from public, anon, authenticated;
grant select on "app_private"."agent_mandates" to authenticated;
grant all on "app_private"."agent_mandates" to service_role;
drop policy if exists agent_mandates_read on "app_private"."agent_mandates";
create policy agent_mandates_read on "app_private"."agent_mandates"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('agent_checkout.read')));

-- Starts a checkout session over a cart, or returns the one this idempotency
-- key made before (replayed true). The same key with another request_hash
-- fails with CHECKOUT_IDEMPOTENCY_CONFLICT. Needs agent_checkout.write.
create or replace function "app_private"."create_checkout_session"(tenant uuid, cart_id uuid, protocol text, idempotency_key text, request_hash text, expires_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."checkout_sessions";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_checkout_session.tenant is not null and coalesce(better_supabase.can('tenant', create_checkout_session.tenant, 'agent_checkout.write'), false))) then
    raise exception 'not allowed to start checkout sessions' using errcode = '42501', hint = 'CHECKOUT_FORBIDDEN';
  end if;
  if create_checkout_session.protocol is null or create_checkout_session.protocol not in ('acp', 'ucp') then
    raise exception 'the protocol is acp or ucp' using errcode = '22023', hint = 'CHECKOUT_INVALID';
  end if;
  if coalesce(create_checkout_session.idempotency_key, '') = '' or coalesce(create_checkout_session.request_hash, '') = '' then
    raise exception 'a checkout session needs an idempotency key' using errcode = '22023', hint = 'CHECKOUT_IDEMPOTENCY_KEY_REQUIRED';
  end if;
  select * into v_row from "app_private"."checkout_sessions" x
  where x."tenant_id" = create_checkout_session.tenant and x."idempotency_key" = create_checkout_session.idempotency_key;
  if found then
    if v_row."request_hash" <> create_checkout_session.request_hash then
      raise exception 'this idempotency key was used with another request' using errcode = '22023', hint = 'CHECKOUT_IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status", 'buyer', v_row."buyer", 'orderId', v_row."order_id", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" in ('open', 'ready') and v_row."expires_at" is not null and v_row."expires_at" <= now()), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('replayed', true);
  end if;
  begin
    insert into "app_private"."checkout_sessions" ("tenant_id", "cart_id", "protocol", "idempotency_key", "request_hash", "expires_at")
    values (create_checkout_session.tenant, create_checkout_session.cart_id, create_checkout_session.protocol,
      create_checkout_session.idempotency_key, create_checkout_session.request_hash, create_checkout_session.expires_at)
    returning * into v_row;
  exception when unique_violation then
    select * into v_row from "app_private"."checkout_sessions" x
    where x."tenant_id" = create_checkout_session.tenant and x."idempotency_key" = create_checkout_session.idempotency_key;
    if not found or v_row."request_hash" <> create_checkout_session.request_hash then
      raise exception 'this idempotency key was used with another request' using errcode = '22023', hint = 'CHECKOUT_IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status", 'buyer', v_row."buyer", 'orderId', v_row."order_id", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" in ('open', 'ready') and v_row."expires_at" is not null and v_row."expires_at" <= now()), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('replayed', true);
  end;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status", 'buyer', v_row."buyer", 'orderId', v_row."order_id", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" in ('open', 'ready') and v_row."expires_at" is not null and v_row."expires_at" <= now()), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('replayed', false);
end;
$$;
revoke execute on function "app_private"."create_checkout_session"(uuid, uuid, text, text, text, timestamptz) from public, anon;
grant execute on function "app_private"."create_checkout_session"(uuid, uuid, text, text, text, timestamptz) to authenticated, service_role;

-- Changes an open session. input may hold buyer (a JSON object), status (open,
-- ready or canceled) and expiresAt. A completed or canceled session is final.
-- Needs agent_checkout.write.
create or replace function "app_private"."update_checkout_session"(session_id uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_input jsonb := coalesce(update_checkout_session.input, '{}'::jsonb);
  v_row "app_private"."checkout_sessions";
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."checkout_sessions" x where x."id" = update_checkout_session.session_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agent_checkout.read'), false))) then
    raise exception 'no such checkout session' using errcode = 'P0002', hint = 'CHECKOUT_SESSION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agent_checkout.write'), false))) then
    raise exception 'not allowed to change checkout sessions' using errcode = '42501', hint = 'CHECKOUT_FORBIDDEN';
  end if;
  if v_row."status" not in ('open', 'ready') then
    raise exception 'the session is completed or canceled' using errcode = '55000', hint = 'CHECKOUT_SESSION_FINAL';
  end if;
  if v_row."expires_at" is not null and v_row."expires_at" <= now() then
    raise exception 'the session expired' using errcode = '55000', hint = 'CHECKOUT_SESSION_EXPIRED';
  end if;
  v_status := coalesce(v_input ->> 'status', v_row."status");
  if v_status not in ('open', 'ready', 'canceled') then
    raise exception 'status is open, ready or canceled' using errcode = '22023', hint = 'CHECKOUT_INVALID';
  end if;
  if v_input ? 'buyer' and jsonb_typeof(v_input -> 'buyer') not in ('object', 'null') then
    raise exception 'buyer is an object or null' using errcode = '22023', hint = 'CHECKOUT_INVALID';
  end if;
  update "app_private"."checkout_sessions" x set
    "status" = v_status,
    "buyer" = case when v_input ? 'buyer' then nullif(v_input -> 'buyer', 'null'::jsonb) else x."buyer" end,
    "expires_at" = case when v_input ? 'expiresAt' then (v_input ->> 'expiresAt')::timestamptz else x."expires_at" end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status", 'buyer', v_row."buyer", 'orderId', v_row."order_id", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" in ('open', 'ready') and v_row."expires_at" is not null and v_row."expires_at" <= now()), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."update_checkout_session"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."update_checkout_session"(uuid, jsonb) to authenticated, service_role;

create or replace function "app_private"."get_checkout_session"(session_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."checkout_sessions";
begin
  select * into v_row from "app_private"."checkout_sessions" x where x."id" = get_checkout_session.session_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agent_checkout.read'), false))) then
    raise exception 'no such checkout session' using errcode = 'P0002', hint = 'CHECKOUT_SESSION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status", 'buyer', v_row."buyer", 'orderId', v_row."order_id", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" in ('open', 'ready') and v_row."expires_at" is not null and v_row."expires_at" <= now()), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."get_checkout_session"(uuid) from public, anon;
grant execute on function "app_private"."get_checkout_session"(uuid) to authenticated, service_role;

-- Sessions, newest first. filters is { status, protocol, cartId, limit, offset }.
create or replace function "app_private"."list_checkout_sessions"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_checkout_sessions.filters, '{}'::jsonb);
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_checkout_sessions.tenant is not null and coalesce(better_supabase.can('tenant', list_checkout_sessions.tenant, 'agent_checkout.read'), false))) then
    raise exception 'not allowed to read checkout sessions' using errcode = '42501', hint = 'CHECKOUT_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'cartId', y."cart_id", 'protocol', y."protocol", 'status', y."status", 'buyer', y."buyer", 'orderId', y."order_id", 'expiresAt', y."expires_at", 'expired', (y."status" in ('open', 'ready') and y."expires_at" is not null and y."expires_at" <= now()), 'createdBy', y."created_by", 'createdAt', y."created_at", 'updatedAt', y."updated_at") order by y."created_at" desc, y."id")
    from (
      select * from "app_private"."checkout_sessions" x
      where x."tenant_id" = list_checkout_sessions.tenant
        and (not v_filters ? 'status' or x."status" = v_filters ->> 'status')
        and (not v_filters ? 'protocol' or x."protocol" = v_filters ->> 'protocol')
        and (not v_filters ? 'cartId' or x."cart_id"::text = v_filters ->> 'cartId')
      order by x."created_at" desc, x."id"
      limit v_limit offset coalesce((v_filters ->> 'offset')::integer, 0)
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "app_private"."list_checkout_sessions"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."list_checkout_sessions"(uuid, jsonb) to authenticated, service_role;

-- Marks a session completed with the order its cart became. Service only: the
-- TypeScript side calls it after the orders checkout placed the order and took
-- the payment through the payment provider. Completing again with the same
-- order returns the session.
create or replace function "app_private"."complete_checkout_session"(session_id uuid, order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."checkout_sessions";
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'only the service role completes checkout sessions' using errcode = '42501', hint = 'CHECKOUT_FORBIDDEN';
  end if;
  select * into v_row from "app_private"."checkout_sessions" x where x."id" = complete_checkout_session.session_id for update;
  if not found then
    raise exception 'no such checkout session' using errcode = 'P0002', hint = 'CHECKOUT_SESSION_NOT_FOUND';
  end if;
  if v_row."status" = 'completed' then
    if v_row."order_id" = complete_checkout_session.order_id then
      return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status", 'buyer', v_row."buyer", 'orderId', v_row."order_id", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" in ('open', 'ready') and v_row."expires_at" is not null and v_row."expires_at" <= now()), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
    end if;
    raise exception 'the session completed with another order' using errcode = '55000', hint = 'CHECKOUT_SESSION_FINAL';
  end if;
  if v_row."status" = 'canceled' then
    raise exception 'the session is canceled' using errcode = '55000', hint = 'CHECKOUT_SESSION_FINAL';
  end if;
  if complete_checkout_session.order_id is null then
    raise exception 'order_id is required' using errcode = '22023', hint = 'CHECKOUT_INVALID';
  end if;
  update "app_private"."checkout_sessions" x set "status" = 'completed', "order_id" = complete_checkout_session.order_id, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status", 'buyer', v_row."buyer", 'orderId', v_row."order_id", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" in ('open', 'ready') and v_row."expires_at" is not null and v_row."expires_at" <= now()), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."complete_checkout_session"(uuid, uuid) from public, anon, authenticated;
grant execute on function "app_private"."complete_checkout_session"(uuid, uuid) to service_role;

-- Stores a verified mandate. input is { vct, credential, credentialHash,
-- issuerKid, subject, expiresAt, sessionId }. Storing the same credential
-- again returns the stored row. Needs agent_checkout.write.
create or replace function "app_private"."store_agent_mandate"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_input jsonb := coalesce(store_agent_mandate.input, '{}'::jsonb);
  v_row "app_private"."agent_mandates";
  v_expires timestamptz;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (store_agent_mandate.tenant is not null and coalesce(better_supabase.can('tenant', store_agent_mandate.tenant, 'agent_checkout.write'), false))) then
    raise exception 'not allowed to store mandates' using errcode = '42501', hint = 'AGENT_MANDATE_FORBIDDEN';
  end if;
  if coalesce(v_input ->> 'vct', '') not in ('mandate.checkout.open.1', 'mandate.checkout.1') then
    raise exception 'vct is mandate.checkout.open.1 or mandate.checkout.1' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
  end if;
  if coalesce(v_input ->> 'credential', '') = '' or coalesce(v_input ->> 'credentialHash', '') = '' or coalesce(v_input ->> 'expiresAt', '') = '' then
    raise exception 'a mandate needs a credential, its hash and an expiry' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
  end if;
  v_expires := (v_input ->> 'expiresAt')::timestamptz;
  if v_expires <= now() then
    raise exception 'the mandate expired' using errcode = '22023', hint = 'AGENT_MANDATE_EXPIRED';
  end if;
  if coalesce(v_input ->> 'sessionId', '') <> '' and not exists (
    select 1 from "app_private"."checkout_sessions" x
    where x."id" = (v_input ->> 'sessionId')::uuid and x."tenant_id" = store_agent_mandate.tenant
  ) then
    raise exception 'no such checkout session' using errcode = 'P0002', hint = 'CHECKOUT_SESSION_NOT_FOUND';
  end if;
  insert into "app_private"."agent_mandates" ("tenant_id", "session_id", "vct", "credential", "credential_hash", "issuer_kid", "subject", "expires_at")
  values (store_agent_mandate.tenant, nullif(v_input ->> 'sessionId', '')::uuid, v_input ->> 'vct', v_input ->> 'credential',
    v_input ->> 'credentialHash', nullif(v_input ->> 'issuerKid', ''), nullif(v_input ->> 'subject', ''), v_expires)
  on conflict ("tenant_id", "credential_hash") do nothing
  returning * into v_row;
  if not found then
    select * into v_row from "app_private"."agent_mandates" x
    where x."tenant_id" = store_agent_mandate.tenant and x."credential_hash" = v_input ->> 'credentialHash';
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'sessionId', v_row."session_id", 'vct', v_row."vct", 'status', v_row."status", 'credential', v_row."credential", 'credentialHash', v_row."credential_hash", 'issuerKid', v_row."issuer_kid", 'subject', v_row."subject", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" = 'active' and v_row."expires_at" <= now()), 'consumedAt', v_row."consumed_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
  end if;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'sessionId', v_row."session_id", 'vct', v_row."vct", 'status', v_row."status", 'credential', v_row."credential", 'credentialHash', v_row."credential_hash", 'issuerKid', v_row."issuer_kid", 'subject', v_row."subject", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" = 'active' and v_row."expires_at" <= now()), 'consumedAt', v_row."consumed_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "app_private"."store_agent_mandate"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."store_agent_mandate"(uuid, jsonb) to authenticated, service_role;

-- Uses a closed mandate once, for one session. An open mandate is never
-- consumed: it keeps authorizing closed ones until it expires or is revoked.
-- Needs agent_checkout.write.
create or replace function "app_private"."consume_agent_mandate"(mandate_id uuid, session_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."agent_mandates";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."agent_mandates" x where x."id" = consume_agent_mandate.mandate_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agent_checkout.read'), false))) then
    raise exception 'no such mandate' using errcode = 'P0002', hint = 'AGENT_MANDATE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agent_checkout.write'), false))) then
    raise exception 'not allowed to use mandates' using errcode = '42501', hint = 'AGENT_MANDATE_FORBIDDEN';
  end if;
  if v_row."vct" <> 'mandate.checkout.1' then
    raise exception 'only a closed mandate is consumed' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
  end if;
  if v_row."status" <> 'active' then
    raise exception 'the mandate was already used or revoked' using errcode = '55000', hint = 'AGENT_MANDATE_USED';
  end if;
  if v_row."expires_at" <= now() then
    raise exception 'the mandate expired' using errcode = '55000', hint = 'AGENT_MANDATE_EXPIRED';
  end if;
  if v_row."session_id" is not null and v_row."session_id" <> consume_agent_mandate.session_id then
    raise exception 'the mandate belongs to another session' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
  end if;
  update "app_private"."agent_mandates" x set "status" = 'consumed', "consumed_at" = now(), "session_id" = coalesce(x."session_id", consume_agent_mandate.session_id)
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'sessionId', v_row."session_id", 'vct', v_row."vct", 'status', v_row."status", 'credential', v_row."credential", 'credentialHash', v_row."credential_hash", 'issuerKid', v_row."issuer_kid", 'subject', v_row."subject", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" = 'active' and v_row."expires_at" <= now()), 'consumedAt', v_row."consumed_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "app_private"."consume_agent_mandate"(uuid, uuid) from public, anon;
grant execute on function "app_private"."consume_agent_mandate"(uuid, uuid) to authenticated, service_role;

-- Revokes an active mandate; false when it was not active. Needs
-- agent_checkout.manage.
create or replace function "app_private"."revoke_agent_mandate"(mandate_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."agent_mandates";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."agent_mandates" x where x."id" = revoke_agent_mandate.mandate_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agent_checkout.read'), false))) then
    raise exception 'no such mandate' using errcode = 'P0002', hint = 'AGENT_MANDATE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agent_checkout.manage'), false))) then
    raise exception 'not allowed to revoke mandates' using errcode = '42501', hint = 'AGENT_MANDATE_FORBIDDEN';
  end if;
  if v_row."status" <> 'active' then
    return false;
  end if;
  update "app_private"."agent_mandates" x set "status" = 'revoked' where x."id" = v_row."id" returning * into v_row;
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."revoke_agent_mandate"(uuid) from public, anon;
grant execute on function "app_private"."revoke_agent_mandate"(uuid) to authenticated, service_role;

create or replace function "app_private"."get_agent_mandate"(mandate_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."agent_mandates";
begin
  select * into v_row from "app_private"."agent_mandates" x where x."id" = get_agent_mandate.mandate_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agent_checkout.read'), false))) then
    raise exception 'no such mandate' using errcode = 'P0002', hint = 'AGENT_MANDATE_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'sessionId', v_row."session_id", 'vct', v_row."vct", 'status', v_row."status", 'credential', v_row."credential", 'credentialHash', v_row."credential_hash", 'issuerKid', v_row."issuer_kid", 'subject', v_row."subject", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" = 'active' and v_row."expires_at" <= now()), 'consumedAt', v_row."consumed_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "app_private"."get_agent_mandate"(uuid) from public, anon;
grant execute on function "app_private"."get_agent_mandate"(uuid) to authenticated, service_role;

-- Mandates, newest first. filters is { sessionId, status, vct, limit, offset }.
create or replace function "app_private"."list_agent_mandates"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_agent_mandates.filters, '{}'::jsonb);
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_agent_mandates.tenant is not null and coalesce(better_supabase.can('tenant', list_agent_mandates.tenant, 'agent_checkout.read'), false))) then
    raise exception 'not allowed to read mandates' using errcode = '42501', hint = 'AGENT_MANDATE_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'sessionId', y."session_id", 'vct', y."vct", 'status', y."status", 'credential', y."credential", 'credentialHash', y."credential_hash", 'issuerKid', y."issuer_kid", 'subject', y."subject", 'expiresAt', y."expires_at", 'expired', (y."status" = 'active' and y."expires_at" <= now()), 'consumedAt', y."consumed_at", 'createdBy', y."created_by", 'createdAt', y."created_at") order by y."created_at" desc, y."id")
    from (
      select * from "app_private"."agent_mandates" x
      where x."tenant_id" = list_agent_mandates.tenant
        and (not v_filters ? 'sessionId' or x."session_id"::text = v_filters ->> 'sessionId')
        and (not v_filters ? 'status' or x."status" = v_filters ->> 'status')
        and (not v_filters ? 'vct' or x."vct" = v_filters ->> 'vct')
      order by x."created_at" desc, x."id"
      limit v_limit offset coalesce((v_filters ->> 'offset')::integer, 0)
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "app_private"."list_agent_mandates"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."list_agent_mandates"(uuid, jsonb) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "app_private"."checkout_sessions";
drop policy if exists bsb_tenant_scope_select on "app_private"."checkout_sessions";
create policy bsb_tenant_scope_select on "app_private"."checkout_sessions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('agent_checkout.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."checkout_sessions";
create policy bsb_tenant_scope_insert on "app_private"."checkout_sessions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."checkout_sessions";
create policy bsb_tenant_scope_update on "app_private"."checkout_sessions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."checkout_sessions";
create policy bsb_tenant_scope_delete on "app_private"."checkout_sessions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."agent_mandates";
drop policy if exists bsb_tenant_scope_select on "app_private"."agent_mandates";
create policy bsb_tenant_scope_select on "app_private"."agent_mandates" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('agent_checkout.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."agent_mandates";
create policy bsb_tenant_scope_insert on "app_private"."agent_mandates" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."agent_mandates";
create policy bsb_tenant_scope_update on "app_private"."agent_mandates" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."agent_mandates";
create policy bsb_tenant_scope_delete on "app_private"."agent_mandates" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

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
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_171_agent_checkout.sql
-- better-supabase module: agent-checkout
-- @bsb-block-data agent-checkout
-- @bsb-hash sha256:f2ff7f54e754107be5e7c58c415111abecc80d24eacb7640b39ab53ea8c96238
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('agent-checkout', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_171_agent_checkout.sql
-- better-supabase module: agent-checkout
-- @bsb-block agent-checkout@1 managed
-- @bsb-hash sha256:cbacd1c80583fc6b16bbb15813fbfccc3cf39df8312decbf4301f2514b995351
-- ACP and UCP checkout sessions over an orders cart with idempotency keys, and AP2 checkout mandates verified with signing keys and used once.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."checkout_sessions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."checkout_sessions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."checkout_sessions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."checkout_sessions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."checkout_sessions";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."agent_mandates";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."agent_mandates";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."agent_mandates";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."agent_mandates";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."agent_mandates";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Agent checkout: ACP and UCP checkout sessions over an orders cart, and AP2
-- mandates stored beside them. The session keeps the protocol state; the cart
-- and the order keep the money (bigint minor units).
create table if not exists "better_supabase"."checkout_sessions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "cart_id" uuid not null,
  "protocol" text not null check ("protocol" in ('acp', 'ucp')),
  "status" text not null default 'open' check ("status" in ('open', 'ready', 'completed', 'canceled')),
  "idempotency_key" text not null check (length("idempotency_key") between 1 and 255),
  "request_hash" text not null check (length("request_hash") between 1 and 128),
  "buyer" jsonb,
  "order_id" uuid,
  "expires_at" timestamptz,
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "idempotency_key"),
  check (("status" = 'completed') = ("order_id" is not null))
);
create index if not exists "checkout_sessions_cart_idx" on "better_supabase"."checkout_sessions" ("cart_id");
alter table "better_supabase"."checkout_sessions" enable row level security;
revoke all on "better_supabase"."checkout_sessions" from public, anon, authenticated;
grant select on "better_supabase"."checkout_sessions" to authenticated;
grant all on "better_supabase"."checkout_sessions" to service_role;
drop policy if exists checkout_sessions_read on "better_supabase"."checkout_sessions";
create policy checkout_sessions_read on "better_supabase"."checkout_sessions"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('agent_checkout.read')));

-- A mandate an agent presents: the compact credential, its hash and the key
-- that signed it. The TypeScript side verifies the signature with the
-- signing-keys block before it stores the row; closed mandates are used once.
create table if not exists "better_supabase"."agent_mandates" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "session_id" uuid references "better_supabase"."checkout_sessions" ("id") on delete set null,
  "vct" text not null check ("vct" in ('mandate.checkout.open.1', 'mandate.checkout.1')),
  "status" text not null default 'active' check ("status" in ('active', 'consumed', 'revoked')),
  "credential" text not null check (length("credential") between 1 and 16384),
  "credential_hash" text not null check (length("credential_hash") between 1 and 128),
  "issuer_kid" text,
  "subject" text,
  "expires_at" timestamptz not null,
  "consumed_at" timestamptz,
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "credential_hash"),
  check (("status" = 'consumed') = ("consumed_at" is not null))
);
create index if not exists "agent_mandates_session_idx" on "better_supabase"."agent_mandates" ("session_id");
alter table "better_supabase"."agent_mandates" enable row level security;
revoke all on "better_supabase"."agent_mandates" from public, anon, authenticated;
grant select on "better_supabase"."agent_mandates" to authenticated;
grant all on "better_supabase"."agent_mandates" to service_role;
drop policy if exists agent_mandates_read on "better_supabase"."agent_mandates";
create policy agent_mandates_read on "better_supabase"."agent_mandates"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('agent_checkout.read')));

-- Starts a checkout session over a cart, or returns the one this idempotency
-- key made before (replayed true). The same key with another request_hash
-- fails with CHECKOUT_IDEMPOTENCY_CONFLICT. Needs agent_checkout.write.
create or replace function "better_supabase"."create_checkout_session"(tenant uuid, cart_id uuid, protocol text, idempotency_key text, request_hash text, expires_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."checkout_sessions";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_checkout_session.tenant is not null and coalesce(better_supabase.can('tenant', create_checkout_session.tenant, 'agent_checkout.write'), false))) then
    raise exception 'not allowed to start checkout sessions' using errcode = '42501', hint = 'CHECKOUT_FORBIDDEN';
  end if;
  if create_checkout_session.protocol is null or create_checkout_session.protocol not in ('acp', 'ucp') then
    raise exception 'the protocol is acp or ucp' using errcode = '22023', hint = 'CHECKOUT_INVALID';
  end if;
  if coalesce(create_checkout_session.idempotency_key, '') = '' or coalesce(create_checkout_session.request_hash, '') = '' then
    raise exception 'a checkout session needs an idempotency key' using errcode = '22023', hint = 'CHECKOUT_IDEMPOTENCY_KEY_REQUIRED';
  end if;
  select * into v_row from "better_supabase"."checkout_sessions" x
  where x."tenant_id" = create_checkout_session.tenant and x."idempotency_key" = create_checkout_session.idempotency_key;
  if found then
    if v_row."request_hash" <> create_checkout_session.request_hash then
      raise exception 'this idempotency key was used with another request' using errcode = '22023', hint = 'CHECKOUT_IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status", 'buyer', v_row."buyer", 'orderId', v_row."order_id", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" in ('open', 'ready') and v_row."expires_at" is not null and v_row."expires_at" <= now()), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('replayed', true);
  end if;
  begin
    insert into "better_supabase"."checkout_sessions" ("tenant_id", "cart_id", "protocol", "idempotency_key", "request_hash", "expires_at")
    values (create_checkout_session.tenant, create_checkout_session.cart_id, create_checkout_session.protocol,
      create_checkout_session.idempotency_key, create_checkout_session.request_hash, create_checkout_session.expires_at)
    returning * into v_row;
  exception when unique_violation then
    select * into v_row from "better_supabase"."checkout_sessions" x
    where x."tenant_id" = create_checkout_session.tenant and x."idempotency_key" = create_checkout_session.idempotency_key;
    if not found or v_row."request_hash" <> create_checkout_session.request_hash then
      raise exception 'this idempotency key was used with another request' using errcode = '22023', hint = 'CHECKOUT_IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status", 'buyer', v_row."buyer", 'orderId', v_row."order_id", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" in ('open', 'ready') and v_row."expires_at" is not null and v_row."expires_at" <= now()), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('replayed', true);
  end;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status", 'buyer', v_row."buyer", 'orderId', v_row."order_id", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" in ('open', 'ready') and v_row."expires_at" is not null and v_row."expires_at" <= now()), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('replayed', false);
end;
$$;
revoke execute on function "better_supabase"."create_checkout_session"(uuid, uuid, text, text, text, timestamptz) from public, anon;
grant execute on function "better_supabase"."create_checkout_session"(uuid, uuid, text, text, text, timestamptz) to authenticated, service_role;

-- Changes an open session. input may hold buyer (a JSON object), status (open,
-- ready or canceled) and expiresAt. A completed or canceled session is final.
-- Needs agent_checkout.write.
create or replace function "better_supabase"."update_checkout_session"(session_id uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_input jsonb := coalesce(update_checkout_session.input, '{}'::jsonb);
  v_row "better_supabase"."checkout_sessions";
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."checkout_sessions" x where x."id" = update_checkout_session.session_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agent_checkout.read'), false))) then
    raise exception 'no such checkout session' using errcode = 'P0002', hint = 'CHECKOUT_SESSION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agent_checkout.write'), false))) then
    raise exception 'not allowed to change checkout sessions' using errcode = '42501', hint = 'CHECKOUT_FORBIDDEN';
  end if;
  if v_row."status" not in ('open', 'ready') then
    raise exception 'the session is completed or canceled' using errcode = '55000', hint = 'CHECKOUT_SESSION_FINAL';
  end if;
  if v_row."expires_at" is not null and v_row."expires_at" <= now() then
    raise exception 'the session expired' using errcode = '55000', hint = 'CHECKOUT_SESSION_EXPIRED';
  end if;
  v_status := coalesce(v_input ->> 'status', v_row."status");
  if v_status not in ('open', 'ready', 'canceled') then
    raise exception 'status is open, ready or canceled' using errcode = '22023', hint = 'CHECKOUT_INVALID';
  end if;
  if v_input ? 'buyer' and jsonb_typeof(v_input -> 'buyer') not in ('object', 'null') then
    raise exception 'buyer is an object or null' using errcode = '22023', hint = 'CHECKOUT_INVALID';
  end if;
  update "better_supabase"."checkout_sessions" x set
    "status" = v_status,
    "buyer" = case when v_input ? 'buyer' then nullif(v_input -> 'buyer', 'null'::jsonb) else x."buyer" end,
    "expires_at" = case when v_input ? 'expiresAt' then (v_input ->> 'expiresAt')::timestamptz else x."expires_at" end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status", 'buyer', v_row."buyer", 'orderId', v_row."order_id", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" in ('open', 'ready') and v_row."expires_at" is not null and v_row."expires_at" <= now()), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_checkout_session"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_checkout_session"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."get_checkout_session"(session_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."checkout_sessions";
begin
  select * into v_row from "better_supabase"."checkout_sessions" x where x."id" = get_checkout_session.session_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agent_checkout.read'), false))) then
    raise exception 'no such checkout session' using errcode = 'P0002', hint = 'CHECKOUT_SESSION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status", 'buyer', v_row."buyer", 'orderId', v_row."order_id", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" in ('open', 'ready') and v_row."expires_at" is not null and v_row."expires_at" <= now()), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."get_checkout_session"(uuid) from public, anon;
grant execute on function "better_supabase"."get_checkout_session"(uuid) to authenticated, service_role;

-- Sessions, newest first. filters is { status, protocol, cartId, limit, offset }.
create or replace function "better_supabase"."list_checkout_sessions"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_checkout_sessions.filters, '{}'::jsonb);
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_checkout_sessions.tenant is not null and coalesce(better_supabase.can('tenant', list_checkout_sessions.tenant, 'agent_checkout.read'), false))) then
    raise exception 'not allowed to read checkout sessions' using errcode = '42501', hint = 'CHECKOUT_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'cartId', y."cart_id", 'protocol', y."protocol", 'status', y."status", 'buyer', y."buyer", 'orderId', y."order_id", 'expiresAt', y."expires_at", 'expired', (y."status" in ('open', 'ready') and y."expires_at" is not null and y."expires_at" <= now()), 'createdBy', y."created_by", 'createdAt', y."created_at", 'updatedAt', y."updated_at") order by y."created_at" desc, y."id")
    from (
      select * from "better_supabase"."checkout_sessions" x
      where x."tenant_id" = list_checkout_sessions.tenant
        and (not v_filters ? 'status' or x."status" = v_filters ->> 'status')
        and (not v_filters ? 'protocol' or x."protocol" = v_filters ->> 'protocol')
        and (not v_filters ? 'cartId' or x."cart_id"::text = v_filters ->> 'cartId')
      order by x."created_at" desc, x."id"
      limit v_limit offset coalesce((v_filters ->> 'offset')::integer, 0)
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_checkout_sessions"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_checkout_sessions"(uuid, jsonb) to authenticated, service_role;

-- Marks a session completed with the order its cart became. Service only: the
-- TypeScript side calls it after the orders checkout placed the order and took
-- the payment through the payment provider. Completing again with the same
-- order returns the session.
create or replace function "better_supabase"."complete_checkout_session"(session_id uuid, order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."checkout_sessions";
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'only the service role completes checkout sessions' using errcode = '42501', hint = 'CHECKOUT_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."checkout_sessions" x where x."id" = complete_checkout_session.session_id for update;
  if not found then
    raise exception 'no such checkout session' using errcode = 'P0002', hint = 'CHECKOUT_SESSION_NOT_FOUND';
  end if;
  if v_row."status" = 'completed' then
    if v_row."order_id" = complete_checkout_session.order_id then
      return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status", 'buyer', v_row."buyer", 'orderId', v_row."order_id", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" in ('open', 'ready') and v_row."expires_at" is not null and v_row."expires_at" <= now()), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
    end if;
    raise exception 'the session completed with another order' using errcode = '55000', hint = 'CHECKOUT_SESSION_FINAL';
  end if;
  if v_row."status" = 'canceled' then
    raise exception 'the session is canceled' using errcode = '55000', hint = 'CHECKOUT_SESSION_FINAL';
  end if;
  if complete_checkout_session.order_id is null then
    raise exception 'order_id is required' using errcode = '22023', hint = 'CHECKOUT_INVALID';
  end if;
  update "better_supabase"."checkout_sessions" x set "status" = 'completed', "order_id" = complete_checkout_session.order_id, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status", 'buyer', v_row."buyer", 'orderId', v_row."order_id", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" in ('open', 'ready') and v_row."expires_at" is not null and v_row."expires_at" <= now()), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."complete_checkout_session"(uuid, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."complete_checkout_session"(uuid, uuid) to service_role;

-- Stores a verified mandate. input is { vct, credential, credentialHash,
-- issuerKid, subject, expiresAt, sessionId }. Storing the same credential
-- again returns the stored row. Needs agent_checkout.write.
create or replace function "better_supabase"."store_agent_mandate"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_input jsonb := coalesce(store_agent_mandate.input, '{}'::jsonb);
  v_row "better_supabase"."agent_mandates";
  v_expires timestamptz;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (store_agent_mandate.tenant is not null and coalesce(better_supabase.can('tenant', store_agent_mandate.tenant, 'agent_checkout.write'), false))) then
    raise exception 'not allowed to store mandates' using errcode = '42501', hint = 'AGENT_MANDATE_FORBIDDEN';
  end if;
  if coalesce(v_input ->> 'vct', '') not in ('mandate.checkout.open.1', 'mandate.checkout.1') then
    raise exception 'vct is mandate.checkout.open.1 or mandate.checkout.1' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
  end if;
  if coalesce(v_input ->> 'credential', '') = '' or coalesce(v_input ->> 'credentialHash', '') = '' or coalesce(v_input ->> 'expiresAt', '') = '' then
    raise exception 'a mandate needs a credential, its hash and an expiry' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
  end if;
  v_expires := (v_input ->> 'expiresAt')::timestamptz;
  if v_expires <= now() then
    raise exception 'the mandate expired' using errcode = '22023', hint = 'AGENT_MANDATE_EXPIRED';
  end if;
  if coalesce(v_input ->> 'sessionId', '') <> '' and not exists (
    select 1 from "better_supabase"."checkout_sessions" x
    where x."id" = (v_input ->> 'sessionId')::uuid and x."tenant_id" = store_agent_mandate.tenant
  ) then
    raise exception 'no such checkout session' using errcode = 'P0002', hint = 'CHECKOUT_SESSION_NOT_FOUND';
  end if;
  insert into "better_supabase"."agent_mandates" ("tenant_id", "session_id", "vct", "credential", "credential_hash", "issuer_kid", "subject", "expires_at")
  values (store_agent_mandate.tenant, nullif(v_input ->> 'sessionId', '')::uuid, v_input ->> 'vct', v_input ->> 'credential',
    v_input ->> 'credentialHash', nullif(v_input ->> 'issuerKid', ''), nullif(v_input ->> 'subject', ''), v_expires)
  on conflict ("tenant_id", "credential_hash") do nothing
  returning * into v_row;
  if not found then
    select * into v_row from "better_supabase"."agent_mandates" x
    where x."tenant_id" = store_agent_mandate.tenant and x."credential_hash" = v_input ->> 'credentialHash';
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'sessionId', v_row."session_id", 'vct', v_row."vct", 'status', v_row."status", 'credential', v_row."credential", 'credentialHash', v_row."credential_hash", 'issuerKid', v_row."issuer_kid", 'subject', v_row."subject", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" = 'active' and v_row."expires_at" <= now()), 'consumedAt', v_row."consumed_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
  end if;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'sessionId', v_row."session_id", 'vct', v_row."vct", 'status', v_row."status", 'credential', v_row."credential", 'credentialHash', v_row."credential_hash", 'issuerKid', v_row."issuer_kid", 'subject', v_row."subject", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" = 'active' and v_row."expires_at" <= now()), 'consumedAt', v_row."consumed_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."store_agent_mandate"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."store_agent_mandate"(uuid, jsonb) to authenticated, service_role;

-- Uses a closed mandate once, for one session. An open mandate is never
-- consumed: it keeps authorizing closed ones until it expires or is revoked.
-- Needs agent_checkout.write.
create or replace function "better_supabase"."consume_agent_mandate"(mandate_id uuid, session_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."agent_mandates";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."agent_mandates" x where x."id" = consume_agent_mandate.mandate_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agent_checkout.read'), false))) then
    raise exception 'no such mandate' using errcode = 'P0002', hint = 'AGENT_MANDATE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agent_checkout.write'), false))) then
    raise exception 'not allowed to use mandates' using errcode = '42501', hint = 'AGENT_MANDATE_FORBIDDEN';
  end if;
  if v_row."vct" <> 'mandate.checkout.1' then
    raise exception 'only a closed mandate is consumed' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
  end if;
  if v_row."status" <> 'active' then
    raise exception 'the mandate was already used or revoked' using errcode = '55000', hint = 'AGENT_MANDATE_USED';
  end if;
  if v_row."expires_at" <= now() then
    raise exception 'the mandate expired' using errcode = '55000', hint = 'AGENT_MANDATE_EXPIRED';
  end if;
  if v_row."session_id" is not null and v_row."session_id" <> consume_agent_mandate.session_id then
    raise exception 'the mandate belongs to another session' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
  end if;
  update "better_supabase"."agent_mandates" x set "status" = 'consumed', "consumed_at" = now(), "session_id" = coalesce(x."session_id", consume_agent_mandate.session_id)
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'sessionId', v_row."session_id", 'vct', v_row."vct", 'status', v_row."status", 'credential', v_row."credential", 'credentialHash', v_row."credential_hash", 'issuerKid', v_row."issuer_kid", 'subject', v_row."subject", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" = 'active' and v_row."expires_at" <= now()), 'consumedAt', v_row."consumed_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."consume_agent_mandate"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."consume_agent_mandate"(uuid, uuid) to authenticated, service_role;

-- Revokes an active mandate; false when it was not active. Needs
-- agent_checkout.manage.
create or replace function "better_supabase"."revoke_agent_mandate"(mandate_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."agent_mandates";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."agent_mandates" x where x."id" = revoke_agent_mandate.mandate_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agent_checkout.read'), false))) then
    raise exception 'no such mandate' using errcode = 'P0002', hint = 'AGENT_MANDATE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agent_checkout.manage'), false))) then
    raise exception 'not allowed to revoke mandates' using errcode = '42501', hint = 'AGENT_MANDATE_FORBIDDEN';
  end if;
  if v_row."status" <> 'active' then
    return false;
  end if;
  update "better_supabase"."agent_mandates" x set "status" = 'revoked' where x."id" = v_row."id" returning * into v_row;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."revoke_agent_mandate"(uuid) from public, anon;
grant execute on function "better_supabase"."revoke_agent_mandate"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."get_agent_mandate"(mandate_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."agent_mandates";
begin
  select * into v_row from "better_supabase"."agent_mandates" x where x."id" = get_agent_mandate.mandate_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agent_checkout.read'), false))) then
    raise exception 'no such mandate' using errcode = 'P0002', hint = 'AGENT_MANDATE_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'sessionId', v_row."session_id", 'vct', v_row."vct", 'status', v_row."status", 'credential', v_row."credential", 'credentialHash', v_row."credential_hash", 'issuerKid', v_row."issuer_kid", 'subject', v_row."subject", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" = 'active' and v_row."expires_at" <= now()), 'consumedAt', v_row."consumed_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."get_agent_mandate"(uuid) from public, anon;
grant execute on function "better_supabase"."get_agent_mandate"(uuid) to authenticated, service_role;

-- Mandates, newest first. filters is { sessionId, status, vct, limit, offset }.
create or replace function "better_supabase"."list_agent_mandates"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_agent_mandates.filters, '{}'::jsonb);
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_agent_mandates.tenant is not null and coalesce(better_supabase.can('tenant', list_agent_mandates.tenant, 'agent_checkout.read'), false))) then
    raise exception 'not allowed to read mandates' using errcode = '42501', hint = 'AGENT_MANDATE_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'sessionId', y."session_id", 'vct', y."vct", 'status', y."status", 'credential', y."credential", 'credentialHash', y."credential_hash", 'issuerKid', y."issuer_kid", 'subject', y."subject", 'expiresAt', y."expires_at", 'expired', (y."status" = 'active' and y."expires_at" <= now()), 'consumedAt', y."consumed_at", 'createdBy', y."created_by", 'createdAt', y."created_at") order by y."created_at" desc, y."id")
    from (
      select * from "better_supabase"."agent_mandates" x
      where x."tenant_id" = list_agent_mandates.tenant
        and (not v_filters ? 'sessionId' or x."session_id"::text = v_filters ->> 'sessionId')
        and (not v_filters ? 'status' or x."status" = v_filters ->> 'status')
        and (not v_filters ? 'vct' or x."vct" = v_filters ->> 'vct')
      order by x."created_at" desc, x."id"
      limit v_limit offset coalesce((v_filters ->> 'offset')::integer, 0)
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_agent_mandates"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_agent_mandates"(uuid, jsonb) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."checkout_sessions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."checkout_sessions";
create policy bsb_tenant_scope_select on "better_supabase"."checkout_sessions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('agent_checkout.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."checkout_sessions";
create policy bsb_tenant_scope_insert on "better_supabase"."checkout_sessions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."checkout_sessions";
create policy bsb_tenant_scope_update on "better_supabase"."checkout_sessions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."checkout_sessions";
create policy bsb_tenant_scope_delete on "better_supabase"."checkout_sessions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."agent_mandates";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."agent_mandates";
create policy bsb_tenant_scope_select on "better_supabase"."agent_mandates" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('agent_checkout.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."agent_mandates";
create policy bsb_tenant_scope_insert on "better_supabase"."agent_mandates" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."agent_mandates";
create policy bsb_tenant_scope_update on "better_supabase"."agent_mandates" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."agent_mandates";
create policy bsb_tenant_scope_delete on "better_supabase"."agent_mandates" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.agent-checkout.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

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

create or replace function "api"."create_checkout_session"(tenant uuid, cart_id uuid, protocol text, idempotency_key text, request_hash text, expires_at timestamptz default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_checkout_session"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."create_checkout_session"(uuid, uuid, text, text, text, timestamptz) from public, anon;
grant execute on function "api"."create_checkout_session"(uuid, uuid, text, text, text, timestamptz) to authenticated, service_role;

create or replace function "api"."update_checkout_session"(session_id uuid, input jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_checkout_session"($1, $2) $$;
revoke execute on function "api"."update_checkout_session"(uuid, jsonb) from public, anon;
grant execute on function "api"."update_checkout_session"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."get_checkout_session"(session_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_checkout_session"($1) $$;
revoke execute on function "api"."get_checkout_session"(uuid) from public, anon;
grant execute on function "api"."get_checkout_session"(uuid) to authenticated, service_role;

create or replace function "api"."list_checkout_sessions"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_checkout_sessions"($1, $2) $$;
revoke execute on function "api"."list_checkout_sessions"(uuid, jsonb) from public, anon;
grant execute on function "api"."list_checkout_sessions"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."complete_checkout_session"(session_id uuid, order_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."complete_checkout_session"($1, $2) $$;
revoke execute on function "api"."complete_checkout_session"(uuid, uuid) from public, anon, authenticated;
grant execute on function "api"."complete_checkout_session"(uuid, uuid) to service_role;

create or replace function "api"."store_agent_mandate"(tenant uuid, input jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."store_agent_mandate"($1, $2) $$;
revoke execute on function "api"."store_agent_mandate"(uuid, jsonb) from public, anon;
grant execute on function "api"."store_agent_mandate"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."consume_agent_mandate"(mandate_id uuid, session_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."consume_agent_mandate"($1, $2) $$;
revoke execute on function "api"."consume_agent_mandate"(uuid, uuid) from public, anon;
grant execute on function "api"."consume_agent_mandate"(uuid, uuid) to authenticated, service_role;

create or replace function "api"."revoke_agent_mandate"(mandate_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."revoke_agent_mandate"($1) $$;
revoke execute on function "api"."revoke_agent_mandate"(uuid) from public, anon;
grant execute on function "api"."revoke_agent_mandate"(uuid) to authenticated, service_role;

create or replace function "api"."get_agent_mandate"(mandate_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_agent_mandate"($1) $$;
revoke execute on function "api"."get_agent_mandate"(uuid) from public, anon;
grant execute on function "api"."get_agent_mandate"(uuid) to authenticated, service_role;

create or replace function "api"."list_agent_mandates"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_agent_mandates"($1, $2) $$;
revoke execute on function "api"."list_agent_mandates"(uuid, jsonb) from public, anon;
grant execute on function "api"."list_agent_mandates"(uuid, jsonb) to authenticated, service_role;

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
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_171_agent_checkout.sql
-- better-supabase module: agent-checkout
-- @bsb-block-data agent-checkout
-- @bsb-hash sha256:f2ff7f54e754107be5e7c58c415111abecc80d24eacb7640b39ab53ea8c96238
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('agent-checkout', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_171_agent_checkout.sql
-- better-supabase module: agent-checkout
-- @bsb-block agent-checkout@1 managed
-- @bsb-hash sha256:8970d9d86c8557c0f5206c547c247a3ecbc0ca9400f6b7e73f639e05116f4cdf
-- ACP and UCP checkout sessions over an orders cart with idempotency keys, and AP2 checkout mandates verified with signing keys and used once.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."checkout_sessions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."checkout_sessions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."checkout_sessions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."checkout_sessions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."checkout_sessions";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."agent_mandates";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."agent_mandates";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."agent_mandates";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."agent_mandates";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."agent_mandates";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Agent checkout: ACP and UCP checkout sessions over an orders cart, and AP2
-- mandates stored beside them. The session keeps the protocol state; the cart
-- and the order keep the money (bigint minor units).
-- better_supabase.checkout_sessions is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."checkout_sessions" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."checkout_sessions" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."checkout_sessions" add column if not exists "cart_id" uuid;
alter table "better_supabase"."checkout_sessions" add column if not exists "protocol" text check ("protocol" in ('acp', 'ucp'));
alter table "better_supabase"."checkout_sessions" add column if not exists "status" text not null default 'open' check ("status" in ('open', 'ready', 'completed', 'canceled'));
alter table "better_supabase"."checkout_sessions" add column if not exists "idempotency_key" text check (length("idempotency_key") between 1 and 255);
alter table "better_supabase"."checkout_sessions" add column if not exists "request_hash" text check (length("request_hash") between 1 and 128);
alter table "better_supabase"."checkout_sessions" add column if not exists "buyer" jsonb;
alter table "better_supabase"."checkout_sessions" add column if not exists "order_id" uuid;
alter table "better_supabase"."checkout_sessions" add column if not exists "expires_at" timestamptz;
alter table "better_supabase"."checkout_sessions" add column if not exists "created_by" uuid default auth.uid();
alter table "better_supabase"."checkout_sessions" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."checkout_sessions" add column if not exists "updated_at" timestamptz not null default now();
create unique index if not exists "bsb_checkout_sessions_tenant_id_key" on "better_supabase"."checkout_sessions" ("tenant_id", "id");
create index if not exists "checkout_sessions_cart_idx" on "better_supabase"."checkout_sessions" ("cart_id");
alter table "better_supabase"."checkout_sessions" enable row level security;
grant select on "better_supabase"."checkout_sessions" to authenticated;
grant all on "better_supabase"."checkout_sessions" to service_role;
drop policy if exists bsb_checkout_sessions_read on "better_supabase"."checkout_sessions";
create policy bsb_checkout_sessions_read on "better_supabase"."checkout_sessions"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('agent_checkout.read')));

-- A mandate an agent presents: the compact credential, its hash and the key
-- that signed it. The TypeScript side verifies the signature with the
-- signing-keys block before it stores the row; closed mandates are used once.
-- better_supabase.agent_mandates is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."agent_mandates" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."agent_mandates" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."agent_mandates" add column if not exists "session_id" uuid;
alter table "better_supabase"."agent_mandates" add column if not exists "vct" text check ("vct" in ('mandate.checkout.open.1', 'mandate.checkout.1'));
alter table "better_supabase"."agent_mandates" add column if not exists "status" text not null default 'active' check ("status" in ('active', 'consumed', 'revoked'));
alter table "better_supabase"."agent_mandates" add column if not exists "credential" text check (length("credential") between 1 and 16384);
alter table "better_supabase"."agent_mandates" add column if not exists "credential_hash" text check (length("credential_hash") between 1 and 128);
alter table "better_supabase"."agent_mandates" add column if not exists "issuer_kid" text;
alter table "better_supabase"."agent_mandates" add column if not exists "subject" text;
alter table "better_supabase"."agent_mandates" add column if not exists "expires_at" timestamptz;
alter table "better_supabase"."agent_mandates" add column if not exists "consumed_at" timestamptz;
alter table "better_supabase"."agent_mandates" add column if not exists "created_by" uuid default auth.uid();
alter table "better_supabase"."agent_mandates" add column if not exists "created_at" timestamptz not null default now();
create unique index if not exists "bsb_agent_mandates_tenant_id_key" on "better_supabase"."agent_mandates" ("tenant_id", "id");
create unique index if not exists "bsb_agent_mandates_tenant_credential_hash_key" on "better_supabase"."agent_mandates" ("tenant_id", "credential_hash");
create index if not exists "agent_mandates_session_idx" on "better_supabase"."agent_mandates" ("session_id");
alter table "better_supabase"."agent_mandates" enable row level security;
grant select on "better_supabase"."agent_mandates" to authenticated;
grant all on "better_supabase"."agent_mandates" to service_role;
drop policy if exists bsb_agent_mandates_read on "better_supabase"."agent_mandates";
create policy bsb_agent_mandates_read on "better_supabase"."agent_mandates"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('agent_checkout.read')));

-- Starts a checkout session over a cart, or returns the one this idempotency
-- key made before (replayed true). The same key with another request_hash
-- fails with CHECKOUT_IDEMPOTENCY_CONFLICT. Needs agent_checkout.write.
create or replace function "better_supabase"."create_checkout_session"(tenant uuid, cart_id uuid, protocol text, idempotency_key text, request_hash text, expires_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."checkout_sessions";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_checkout_session.tenant is not null and coalesce(better_supabase.can('tenant', create_checkout_session.tenant, 'agent_checkout.write'), false))) then
    raise exception 'not allowed to start checkout sessions' using errcode = '42501', hint = 'CHECKOUT_FORBIDDEN';
  end if;
  if create_checkout_session.protocol is null or create_checkout_session.protocol not in ('acp', 'ucp') then
    raise exception 'the protocol is acp or ucp' using errcode = '22023', hint = 'CHECKOUT_INVALID';
  end if;
  if coalesce(create_checkout_session.idempotency_key, '') = '' or coalesce(create_checkout_session.request_hash, '') = '' then
    raise exception 'a checkout session needs an idempotency key' using errcode = '22023', hint = 'CHECKOUT_IDEMPOTENCY_KEY_REQUIRED';
  end if;
  select * into v_row from "better_supabase"."checkout_sessions" x
  where x."tenant_id" = create_checkout_session.tenant and x."idempotency_key" = create_checkout_session.idempotency_key;
  if found then
    if v_row."request_hash" <> create_checkout_session.request_hash then
      raise exception 'this idempotency key was used with another request' using errcode = '22023', hint = 'CHECKOUT_IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status", 'buyer', v_row."buyer", 'orderId', v_row."order_id", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" in ('open', 'ready') and v_row."expires_at" is not null and v_row."expires_at" <= now()), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('replayed', true);
  end if;
  begin
    insert into "better_supabase"."checkout_sessions" ("tenant_id", "cart_id", "protocol", "idempotency_key", "request_hash", "expires_at")
    values (create_checkout_session.tenant, create_checkout_session.cart_id, create_checkout_session.protocol,
      create_checkout_session.idempotency_key, create_checkout_session.request_hash, create_checkout_session.expires_at)
    returning * into v_row;
  exception when unique_violation then
    select * into v_row from "better_supabase"."checkout_sessions" x
    where x."tenant_id" = create_checkout_session.tenant and x."idempotency_key" = create_checkout_session.idempotency_key;
    if not found or v_row."request_hash" <> create_checkout_session.request_hash then
      raise exception 'this idempotency key was used with another request' using errcode = '22023', hint = 'CHECKOUT_IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status", 'buyer', v_row."buyer", 'orderId', v_row."order_id", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" in ('open', 'ready') and v_row."expires_at" is not null and v_row."expires_at" <= now()), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('replayed', true);
  end;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status", 'buyer', v_row."buyer", 'orderId', v_row."order_id", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" in ('open', 'ready') and v_row."expires_at" is not null and v_row."expires_at" <= now()), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('replayed', false);
end;
$$;
revoke execute on function "better_supabase"."create_checkout_session"(uuid, uuid, text, text, text, timestamptz) from public, anon;
grant execute on function "better_supabase"."create_checkout_session"(uuid, uuid, text, text, text, timestamptz) to authenticated, service_role;

-- Changes an open session. input may hold buyer (a JSON object), status (open,
-- ready or canceled) and expiresAt. A completed or canceled session is final.
-- Needs agent_checkout.write.
create or replace function "better_supabase"."update_checkout_session"(session_id uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_input jsonb := coalesce(update_checkout_session.input, '{}'::jsonb);
  v_row "better_supabase"."checkout_sessions";
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."checkout_sessions" x where x."id" = update_checkout_session.session_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agent_checkout.read'), false))) then
    raise exception 'no such checkout session' using errcode = 'P0002', hint = 'CHECKOUT_SESSION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agent_checkout.write'), false))) then
    raise exception 'not allowed to change checkout sessions' using errcode = '42501', hint = 'CHECKOUT_FORBIDDEN';
  end if;
  if v_row."status" not in ('open', 'ready') then
    raise exception 'the session is completed or canceled' using errcode = '55000', hint = 'CHECKOUT_SESSION_FINAL';
  end if;
  if v_row."expires_at" is not null and v_row."expires_at" <= now() then
    raise exception 'the session expired' using errcode = '55000', hint = 'CHECKOUT_SESSION_EXPIRED';
  end if;
  v_status := coalesce(v_input ->> 'status', v_row."status");
  if v_status not in ('open', 'ready', 'canceled') then
    raise exception 'status is open, ready or canceled' using errcode = '22023', hint = 'CHECKOUT_INVALID';
  end if;
  if v_input ? 'buyer' and jsonb_typeof(v_input -> 'buyer') not in ('object', 'null') then
    raise exception 'buyer is an object or null' using errcode = '22023', hint = 'CHECKOUT_INVALID';
  end if;
  update "better_supabase"."checkout_sessions" x set
    "status" = v_status,
    "buyer" = case when v_input ? 'buyer' then nullif(v_input -> 'buyer', 'null'::jsonb) else x."buyer" end,
    "expires_at" = case when v_input ? 'expiresAt' then (v_input ->> 'expiresAt')::timestamptz else x."expires_at" end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status", 'buyer', v_row."buyer", 'orderId', v_row."order_id", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" in ('open', 'ready') and v_row."expires_at" is not null and v_row."expires_at" <= now()), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_checkout_session"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_checkout_session"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."get_checkout_session"(session_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."checkout_sessions";
begin
  select * into v_row from "better_supabase"."checkout_sessions" x where x."id" = get_checkout_session.session_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agent_checkout.read'), false))) then
    raise exception 'no such checkout session' using errcode = 'P0002', hint = 'CHECKOUT_SESSION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status", 'buyer', v_row."buyer", 'orderId', v_row."order_id", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" in ('open', 'ready') and v_row."expires_at" is not null and v_row."expires_at" <= now()), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."get_checkout_session"(uuid) from public, anon;
grant execute on function "better_supabase"."get_checkout_session"(uuid) to authenticated, service_role;

-- Sessions, newest first. filters is { status, protocol, cartId, limit, offset }.
create or replace function "better_supabase"."list_checkout_sessions"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_checkout_sessions.filters, '{}'::jsonb);
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_checkout_sessions.tenant is not null and coalesce(better_supabase.can('tenant', list_checkout_sessions.tenant, 'agent_checkout.read'), false))) then
    raise exception 'not allowed to read checkout sessions' using errcode = '42501', hint = 'CHECKOUT_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'cartId', y."cart_id", 'protocol', y."protocol", 'status', y."status", 'buyer', y."buyer", 'orderId', y."order_id", 'expiresAt', y."expires_at", 'expired', (y."status" in ('open', 'ready') and y."expires_at" is not null and y."expires_at" <= now()), 'createdBy', y."created_by", 'createdAt', y."created_at", 'updatedAt', y."updated_at") order by y."created_at" desc, y."id")
    from (
      select * from "better_supabase"."checkout_sessions" x
      where x."tenant_id" = list_checkout_sessions.tenant
        and (not v_filters ? 'status' or x."status" = v_filters ->> 'status')
        and (not v_filters ? 'protocol' or x."protocol" = v_filters ->> 'protocol')
        and (not v_filters ? 'cartId' or x."cart_id"::text = v_filters ->> 'cartId')
      order by x."created_at" desc, x."id"
      limit v_limit offset coalesce((v_filters ->> 'offset')::integer, 0)
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_checkout_sessions"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_checkout_sessions"(uuid, jsonb) to authenticated, service_role;

-- Marks a session completed with the order its cart became. Service only: the
-- TypeScript side calls it after the orders checkout placed the order and took
-- the payment through the payment provider. Completing again with the same
-- order returns the session.
create or replace function "better_supabase"."complete_checkout_session"(session_id uuid, order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."checkout_sessions";
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'only the service role completes checkout sessions' using errcode = '42501', hint = 'CHECKOUT_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."checkout_sessions" x where x."id" = complete_checkout_session.session_id for update;
  if not found then
    raise exception 'no such checkout session' using errcode = 'P0002', hint = 'CHECKOUT_SESSION_NOT_FOUND';
  end if;
  if v_row."status" = 'completed' then
    if v_row."order_id" = complete_checkout_session.order_id then
      return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status", 'buyer', v_row."buyer", 'orderId', v_row."order_id", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" in ('open', 'ready') and v_row."expires_at" is not null and v_row."expires_at" <= now()), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
    end if;
    raise exception 'the session completed with another order' using errcode = '55000', hint = 'CHECKOUT_SESSION_FINAL';
  end if;
  if v_row."status" = 'canceled' then
    raise exception 'the session is canceled' using errcode = '55000', hint = 'CHECKOUT_SESSION_FINAL';
  end if;
  if complete_checkout_session.order_id is null then
    raise exception 'order_id is required' using errcode = '22023', hint = 'CHECKOUT_INVALID';
  end if;
  update "better_supabase"."checkout_sessions" x set "status" = 'completed', "order_id" = complete_checkout_session.order_id, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status", 'buyer', v_row."buyer", 'orderId', v_row."order_id", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" in ('open', 'ready') and v_row."expires_at" is not null and v_row."expires_at" <= now()), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."complete_checkout_session"(uuid, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."complete_checkout_session"(uuid, uuid) to service_role;

-- Stores a verified mandate. input is { vct, credential, credentialHash,
-- issuerKid, subject, expiresAt, sessionId }. Storing the same credential
-- again returns the stored row. Needs agent_checkout.write.
create or replace function "better_supabase"."store_agent_mandate"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_input jsonb := coalesce(store_agent_mandate.input, '{}'::jsonb);
  v_row "better_supabase"."agent_mandates";
  v_expires timestamptz;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (store_agent_mandate.tenant is not null and coalesce(better_supabase.can('tenant', store_agent_mandate.tenant, 'agent_checkout.write'), false))) then
    raise exception 'not allowed to store mandates' using errcode = '42501', hint = 'AGENT_MANDATE_FORBIDDEN';
  end if;
  if coalesce(v_input ->> 'vct', '') not in ('mandate.checkout.open.1', 'mandate.checkout.1') then
    raise exception 'vct is mandate.checkout.open.1 or mandate.checkout.1' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
  end if;
  if coalesce(v_input ->> 'credential', '') = '' or coalesce(v_input ->> 'credentialHash', '') = '' or coalesce(v_input ->> 'expiresAt', '') = '' then
    raise exception 'a mandate needs a credential, its hash and an expiry' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
  end if;
  v_expires := (v_input ->> 'expiresAt')::timestamptz;
  if v_expires <= now() then
    raise exception 'the mandate expired' using errcode = '22023', hint = 'AGENT_MANDATE_EXPIRED';
  end if;
  if coalesce(v_input ->> 'sessionId', '') <> '' and not exists (
    select 1 from "better_supabase"."checkout_sessions" x
    where x."id" = (v_input ->> 'sessionId')::uuid and x."tenant_id" = store_agent_mandate.tenant
  ) then
    raise exception 'no such checkout session' using errcode = 'P0002', hint = 'CHECKOUT_SESSION_NOT_FOUND';
  end if;
  insert into "better_supabase"."agent_mandates" ("tenant_id", "session_id", "vct", "credential", "credential_hash", "issuer_kid", "subject", "expires_at")
  values (store_agent_mandate.tenant, nullif(v_input ->> 'sessionId', '')::uuid, v_input ->> 'vct', v_input ->> 'credential',
    v_input ->> 'credentialHash', nullif(v_input ->> 'issuerKid', ''), nullif(v_input ->> 'subject', ''), v_expires)
  on conflict ("tenant_id", "credential_hash") do nothing
  returning * into v_row;
  if not found then
    select * into v_row from "better_supabase"."agent_mandates" x
    where x."tenant_id" = store_agent_mandate.tenant and x."credential_hash" = v_input ->> 'credentialHash';
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'sessionId', v_row."session_id", 'vct', v_row."vct", 'status', v_row."status", 'credential', v_row."credential", 'credentialHash', v_row."credential_hash", 'issuerKid', v_row."issuer_kid", 'subject', v_row."subject", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" = 'active' and v_row."expires_at" <= now()), 'consumedAt', v_row."consumed_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
  end if;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'sessionId', v_row."session_id", 'vct', v_row."vct", 'status', v_row."status", 'credential', v_row."credential", 'credentialHash', v_row."credential_hash", 'issuerKid', v_row."issuer_kid", 'subject', v_row."subject", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" = 'active' and v_row."expires_at" <= now()), 'consumedAt', v_row."consumed_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."store_agent_mandate"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."store_agent_mandate"(uuid, jsonb) to authenticated, service_role;

-- Uses a closed mandate once, for one session. An open mandate is never
-- consumed: it keeps authorizing closed ones until it expires or is revoked.
-- Needs agent_checkout.write.
create or replace function "better_supabase"."consume_agent_mandate"(mandate_id uuid, session_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."agent_mandates";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."agent_mandates" x where x."id" = consume_agent_mandate.mandate_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agent_checkout.read'), false))) then
    raise exception 'no such mandate' using errcode = 'P0002', hint = 'AGENT_MANDATE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agent_checkout.write'), false))) then
    raise exception 'not allowed to use mandates' using errcode = '42501', hint = 'AGENT_MANDATE_FORBIDDEN';
  end if;
  if v_row."vct" <> 'mandate.checkout.1' then
    raise exception 'only a closed mandate is consumed' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
  end if;
  if v_row."status" <> 'active' then
    raise exception 'the mandate was already used or revoked' using errcode = '55000', hint = 'AGENT_MANDATE_USED';
  end if;
  if v_row."expires_at" <= now() then
    raise exception 'the mandate expired' using errcode = '55000', hint = 'AGENT_MANDATE_EXPIRED';
  end if;
  if v_row."session_id" is not null and v_row."session_id" <> consume_agent_mandate.session_id then
    raise exception 'the mandate belongs to another session' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
  end if;
  update "better_supabase"."agent_mandates" x set "status" = 'consumed', "consumed_at" = now(), "session_id" = coalesce(x."session_id", consume_agent_mandate.session_id)
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'sessionId', v_row."session_id", 'vct', v_row."vct", 'status', v_row."status", 'credential', v_row."credential", 'credentialHash', v_row."credential_hash", 'issuerKid', v_row."issuer_kid", 'subject', v_row."subject", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" = 'active' and v_row."expires_at" <= now()), 'consumedAt', v_row."consumed_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."consume_agent_mandate"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."consume_agent_mandate"(uuid, uuid) to authenticated, service_role;

-- Revokes an active mandate; false when it was not active. Needs
-- agent_checkout.manage.
create or replace function "better_supabase"."revoke_agent_mandate"(mandate_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."agent_mandates";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."agent_mandates" x where x."id" = revoke_agent_mandate.mandate_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agent_checkout.read'), false))) then
    raise exception 'no such mandate' using errcode = 'P0002', hint = 'AGENT_MANDATE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agent_checkout.manage'), false))) then
    raise exception 'not allowed to revoke mandates' using errcode = '42501', hint = 'AGENT_MANDATE_FORBIDDEN';
  end if;
  if v_row."status" <> 'active' then
    return false;
  end if;
  update "better_supabase"."agent_mandates" x set "status" = 'revoked' where x."id" = v_row."id" returning * into v_row;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."revoke_agent_mandate"(uuid) from public, anon;
grant execute on function "better_supabase"."revoke_agent_mandate"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."get_agent_mandate"(mandate_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."agent_mandates";
begin
  select * into v_row from "better_supabase"."agent_mandates" x where x."id" = get_agent_mandate.mandate_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agent_checkout.read'), false))) then
    raise exception 'no such mandate' using errcode = 'P0002', hint = 'AGENT_MANDATE_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'sessionId', v_row."session_id", 'vct', v_row."vct", 'status', v_row."status", 'credential', v_row."credential", 'credentialHash', v_row."credential_hash", 'issuerKid', v_row."issuer_kid", 'subject', v_row."subject", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" = 'active' and v_row."expires_at" <= now()), 'consumedAt', v_row."consumed_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."get_agent_mandate"(uuid) from public, anon;
grant execute on function "better_supabase"."get_agent_mandate"(uuid) to authenticated, service_role;

-- Mandates, newest first. filters is { sessionId, status, vct, limit, offset }.
create or replace function "better_supabase"."list_agent_mandates"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_agent_mandates.filters, '{}'::jsonb);
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_agent_mandates.tenant is not null and coalesce(better_supabase.can('tenant', list_agent_mandates.tenant, 'agent_checkout.read'), false))) then
    raise exception 'not allowed to read mandates' using errcode = '42501', hint = 'AGENT_MANDATE_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'sessionId', y."session_id", 'vct', y."vct", 'status', y."status", 'credential', y."credential", 'credentialHash', y."credential_hash", 'issuerKid', y."issuer_kid", 'subject', y."subject", 'expiresAt', y."expires_at", 'expired', (y."status" = 'active' and y."expires_at" <= now()), 'consumedAt', y."consumed_at", 'createdBy', y."created_by", 'createdAt', y."created_at") order by y."created_at" desc, y."id")
    from (
      select * from "better_supabase"."agent_mandates" x
      where x."tenant_id" = list_agent_mandates.tenant
        and (not v_filters ? 'sessionId' or x."session_id"::text = v_filters ->> 'sessionId')
        and (not v_filters ? 'status' or x."status" = v_filters ->> 'status')
        and (not v_filters ? 'vct' or x."vct" = v_filters ->> 'vct')
      order by x."created_at" desc, x."id"
      limit v_limit offset coalesce((v_filters ->> 'offset')::integer, 0)
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_agent_mandates"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_agent_mandates"(uuid, jsonb) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."checkout_sessions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."checkout_sessions";
create policy bsb_tenant_scope_select on "better_supabase"."checkout_sessions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('agent_checkout.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."checkout_sessions";
create policy bsb_tenant_scope_insert on "better_supabase"."checkout_sessions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."checkout_sessions";
create policy bsb_tenant_scope_update on "better_supabase"."checkout_sessions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."checkout_sessions";
create policy bsb_tenant_scope_delete on "better_supabase"."checkout_sessions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."agent_mandates";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."agent_mandates";
create policy bsb_tenant_scope_select on "better_supabase"."agent_mandates" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('agent_checkout.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."agent_mandates";
create policy bsb_tenant_scope_insert on "better_supabase"."agent_mandates" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."agent_mandates";
create policy bsb_tenant_scope_update on "better_supabase"."agent_mandates" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."agent_mandates";
create policy bsb_tenant_scope_delete on "better_supabase"."agent_mandates" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

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
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_171_agent_checkout.sql
-- better-supabase module: agent-checkout
-- @bsb-block-data agent-checkout
-- @bsb-hash sha256:f2ff7f54e754107be5e7c58c415111abecc80d24eacb7640b39ab53ea8c96238
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('agent-checkout', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_171_agent_checkout.sql
-- better-supabase module: agent-checkout
-- @bsb-block agent-checkout@1 managed
-- @bsb-hash sha256:7247f6f8624c4bb3994089eb12608ca8f7d2f8a2e3298a72496b91ec0103a35f
-- ACP and UCP checkout sessions over an orders cart with idempotency keys, and AP2 checkout mandates verified with signing keys and used once.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."checkout_sessions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."checkout_sessions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."checkout_sessions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."checkout_sessions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."checkout_sessions";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."agent_mandates";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."agent_mandates";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."agent_mandates";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."agent_mandates";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."agent_mandates";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Agent checkout: ACP and UCP checkout sessions over an orders cart, and AP2
-- mandates stored beside them. The session keeps the protocol state; the cart
-- and the order keep the money (bigint minor units).
create table if not exists "better_supabase"."checkout_sessions" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "cart_id" uuid not null,
  "protocol" text not null check ("protocol" in ('acp', 'ucp')),
  "status" text not null default 'open' check ("status" in ('open', 'ready', 'completed', 'canceled')),
  "idempotency_key" text not null check (length("idempotency_key") between 1 and 255),
  "request_hash" text not null check (length("request_hash") between 1 and 128),
  "buyer" jsonb,
  "order_id" uuid,
  "expires_at" timestamptz,
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("org_id", "idempotency_key"),
  check (("status" = 'completed') = ("order_id" is not null))
);
create index if not exists "checkout_sessions_cart_idx" on "better_supabase"."checkout_sessions" ("cart_id");
alter table "better_supabase"."checkout_sessions" enable row level security;
revoke all on "better_supabase"."checkout_sessions" from public, anon, authenticated;
grant select on "better_supabase"."checkout_sessions" to authenticated;
grant all on "better_supabase"."checkout_sessions" to service_role;
drop policy if exists checkout_sessions_read on "better_supabase"."checkout_sessions";
create policy checkout_sessions_read on "better_supabase"."checkout_sessions"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('agent_checkout.read')));

-- A mandate an agent presents: the compact credential, its hash and the key
-- that signed it. The TypeScript side verifies the signature with the
-- signing-keys block before it stores the row; closed mandates are used once.
create table if not exists "better_supabase"."agent_mandates" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "session_id" uuid references "better_supabase"."checkout_sessions" ("id") on delete set null,
  "vct" text not null check ("vct" in ('mandate.checkout.open.1', 'mandate.checkout.1')),
  "status" text not null default 'active' check ("status" in ('active', 'consumed', 'revoked')),
  "credential" text not null check (length("credential") between 1 and 16384),
  "credential_hash" text not null check (length("credential_hash") between 1 and 128),
  "issuer_kid" text,
  "subject" text,
  "expires_at" timestamptz not null,
  "consumed_at" timestamptz,
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  unique ("org_id", "credential_hash"),
  check (("status" = 'consumed') = ("consumed_at" is not null))
);
create index if not exists "agent_mandates_session_idx" on "better_supabase"."agent_mandates" ("session_id");
alter table "better_supabase"."agent_mandates" enable row level security;
revoke all on "better_supabase"."agent_mandates" from public, anon, authenticated;
grant select on "better_supabase"."agent_mandates" to authenticated;
grant all on "better_supabase"."agent_mandates" to service_role;
drop policy if exists agent_mandates_read on "better_supabase"."agent_mandates";
create policy agent_mandates_read on "better_supabase"."agent_mandates"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('agent_checkout.read')));

-- Starts a checkout session over a cart, or returns the one this idempotency
-- key made before (replayed true). The same key with another request_hash
-- fails with CHECKOUT_IDEMPOTENCY_CONFLICT. Needs agent_checkout.write.
create or replace function "better_supabase"."create_checkout_session"(tenant uuid, cart_id uuid, protocol text, idempotency_key text, request_hash text, expires_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."checkout_sessions";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_checkout_session.tenant is not null and coalesce(better_supabase.can('tenant', create_checkout_session.tenant, 'agent_checkout.write'), false))) then
    raise exception 'not allowed to start checkout sessions' using errcode = '42501', hint = 'CHECKOUT_FORBIDDEN';
  end if;
  if create_checkout_session.protocol is null or create_checkout_session.protocol not in ('acp', 'ucp') then
    raise exception 'the protocol is acp or ucp' using errcode = '22023', hint = 'CHECKOUT_INVALID';
  end if;
  if coalesce(create_checkout_session.idempotency_key, '') = '' or coalesce(create_checkout_session.request_hash, '') = '' then
    raise exception 'a checkout session needs an idempotency key' using errcode = '22023', hint = 'CHECKOUT_IDEMPOTENCY_KEY_REQUIRED';
  end if;
  select * into v_row from "better_supabase"."checkout_sessions" x
  where x."org_id" = create_checkout_session.tenant and x."idempotency_key" = create_checkout_session.idempotency_key;
  if found then
    if v_row."request_hash" <> create_checkout_session.request_hash then
      raise exception 'this idempotency key was used with another request' using errcode = '22023', hint = 'CHECKOUT_IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status", 'buyer', v_row."buyer", 'orderId', v_row."order_id", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" in ('open', 'ready') and v_row."expires_at" is not null and v_row."expires_at" <= now()), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('replayed', true);
  end if;
  begin
    insert into "better_supabase"."checkout_sessions" ("org_id", "cart_id", "protocol", "idempotency_key", "request_hash", "expires_at")
    values (create_checkout_session.tenant, create_checkout_session.cart_id, create_checkout_session.protocol,
      create_checkout_session.idempotency_key, create_checkout_session.request_hash, create_checkout_session.expires_at)
    returning * into v_row;
  exception when unique_violation then
    select * into v_row from "better_supabase"."checkout_sessions" x
    where x."org_id" = create_checkout_session.tenant and x."idempotency_key" = create_checkout_session.idempotency_key;
    if not found or v_row."request_hash" <> create_checkout_session.request_hash then
      raise exception 'this idempotency key was used with another request' using errcode = '22023', hint = 'CHECKOUT_IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status", 'buyer', v_row."buyer", 'orderId', v_row."order_id", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" in ('open', 'ready') and v_row."expires_at" is not null and v_row."expires_at" <= now()), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('replayed', true);
  end;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status", 'buyer', v_row."buyer", 'orderId', v_row."order_id", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" in ('open', 'ready') and v_row."expires_at" is not null and v_row."expires_at" <= now()), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('replayed', false);
end;
$$;
revoke execute on function "better_supabase"."create_checkout_session"(uuid, uuid, text, text, text, timestamptz) from public, anon;
grant execute on function "better_supabase"."create_checkout_session"(uuid, uuid, text, text, text, timestamptz) to authenticated, service_role;

-- Changes an open session. input may hold buyer (a JSON object), status (open,
-- ready or canceled) and expiresAt. A completed or canceled session is final.
-- Needs agent_checkout.write.
create or replace function "better_supabase"."update_checkout_session"(session_id uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_input jsonb := coalesce(update_checkout_session.input, '{}'::jsonb);
  v_row "better_supabase"."checkout_sessions";
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."checkout_sessions" x where x."id" = update_checkout_session.session_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'agent_checkout.read'), false))) then
    raise exception 'no such checkout session' using errcode = 'P0002', hint = 'CHECKOUT_SESSION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'agent_checkout.write'), false))) then
    raise exception 'not allowed to change checkout sessions' using errcode = '42501', hint = 'CHECKOUT_FORBIDDEN';
  end if;
  if v_row."status" not in ('open', 'ready') then
    raise exception 'the session is completed or canceled' using errcode = '55000', hint = 'CHECKOUT_SESSION_FINAL';
  end if;
  if v_row."expires_at" is not null and v_row."expires_at" <= now() then
    raise exception 'the session expired' using errcode = '55000', hint = 'CHECKOUT_SESSION_EXPIRED';
  end if;
  v_status := coalesce(v_input ->> 'status', v_row."status");
  if v_status not in ('open', 'ready', 'canceled') then
    raise exception 'status is open, ready or canceled' using errcode = '22023', hint = 'CHECKOUT_INVALID';
  end if;
  if v_input ? 'buyer' and jsonb_typeof(v_input -> 'buyer') not in ('object', 'null') then
    raise exception 'buyer is an object or null' using errcode = '22023', hint = 'CHECKOUT_INVALID';
  end if;
  update "better_supabase"."checkout_sessions" x set
    "status" = v_status,
    "buyer" = case when v_input ? 'buyer' then nullif(v_input -> 'buyer', 'null'::jsonb) else x."buyer" end,
    "expires_at" = case when v_input ? 'expiresAt' then (v_input ->> 'expiresAt')::timestamptz else x."expires_at" end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status", 'buyer', v_row."buyer", 'orderId', v_row."order_id", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" in ('open', 'ready') and v_row."expires_at" is not null and v_row."expires_at" <= now()), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_checkout_session"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_checkout_session"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."get_checkout_session"(session_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."checkout_sessions";
begin
  select * into v_row from "better_supabase"."checkout_sessions" x where x."id" = get_checkout_session.session_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'agent_checkout.read'), false))) then
    raise exception 'no such checkout session' using errcode = 'P0002', hint = 'CHECKOUT_SESSION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status", 'buyer', v_row."buyer", 'orderId', v_row."order_id", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" in ('open', 'ready') and v_row."expires_at" is not null and v_row."expires_at" <= now()), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."get_checkout_session"(uuid) from public, anon;
grant execute on function "better_supabase"."get_checkout_session"(uuid) to authenticated, service_role;

-- Sessions, newest first. filters is { status, protocol, cartId, limit, offset }.
create or replace function "better_supabase"."list_checkout_sessions"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_checkout_sessions.filters, '{}'::jsonb);
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_checkout_sessions.tenant is not null and coalesce(better_supabase.can('tenant', list_checkout_sessions.tenant, 'agent_checkout.read'), false))) then
    raise exception 'not allowed to read checkout sessions' using errcode = '42501', hint = 'CHECKOUT_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."org_id", 'cartId', y."cart_id", 'protocol', y."protocol", 'status', y."status", 'buyer', y."buyer", 'orderId', y."order_id", 'expiresAt', y."expires_at", 'expired', (y."status" in ('open', 'ready') and y."expires_at" is not null and y."expires_at" <= now()), 'createdBy', y."created_by", 'createdAt', y."created_at", 'updatedAt', y."updated_at") order by y."created_at" desc, y."id")
    from (
      select * from "better_supabase"."checkout_sessions" x
      where x."org_id" = list_checkout_sessions.tenant
        and (not v_filters ? 'status' or x."status" = v_filters ->> 'status')
        and (not v_filters ? 'protocol' or x."protocol" = v_filters ->> 'protocol')
        and (not v_filters ? 'cartId' or x."cart_id"::text = v_filters ->> 'cartId')
      order by x."created_at" desc, x."id"
      limit v_limit offset coalesce((v_filters ->> 'offset')::integer, 0)
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_checkout_sessions"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_checkout_sessions"(uuid, jsonb) to authenticated, service_role;

-- Marks a session completed with the order its cart became. Service only: the
-- TypeScript side calls it after the orders checkout placed the order and took
-- the payment through the payment provider. Completing again with the same
-- order returns the session.
create or replace function "better_supabase"."complete_checkout_session"(session_id uuid, order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."checkout_sessions";
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'only the service role completes checkout sessions' using errcode = '42501', hint = 'CHECKOUT_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."checkout_sessions" x where x."id" = complete_checkout_session.session_id for update;
  if not found then
    raise exception 'no such checkout session' using errcode = 'P0002', hint = 'CHECKOUT_SESSION_NOT_FOUND';
  end if;
  if v_row."status" = 'completed' then
    if v_row."order_id" = complete_checkout_session.order_id then
      return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status", 'buyer', v_row."buyer", 'orderId', v_row."order_id", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" in ('open', 'ready') and v_row."expires_at" is not null and v_row."expires_at" <= now()), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
    end if;
    raise exception 'the session completed with another order' using errcode = '55000', hint = 'CHECKOUT_SESSION_FINAL';
  end if;
  if v_row."status" = 'canceled' then
    raise exception 'the session is canceled' using errcode = '55000', hint = 'CHECKOUT_SESSION_FINAL';
  end if;
  if complete_checkout_session.order_id is null then
    raise exception 'order_id is required' using errcode = '22023', hint = 'CHECKOUT_INVALID';
  end if;
  update "better_supabase"."checkout_sessions" x set "status" = 'completed', "order_id" = complete_checkout_session.order_id, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'cartId', v_row."cart_id", 'protocol', v_row."protocol", 'status', v_row."status", 'buyer', v_row."buyer", 'orderId', v_row."order_id", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" in ('open', 'ready') and v_row."expires_at" is not null and v_row."expires_at" <= now()), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."complete_checkout_session"(uuid, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."complete_checkout_session"(uuid, uuid) to service_role;

-- Stores a verified mandate. input is { vct, credential, credentialHash,
-- issuerKid, subject, expiresAt, sessionId }. Storing the same credential
-- again returns the stored row. Needs agent_checkout.write.
create or replace function "better_supabase"."store_agent_mandate"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_input jsonb := coalesce(store_agent_mandate.input, '{}'::jsonb);
  v_row "better_supabase"."agent_mandates";
  v_expires timestamptz;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (store_agent_mandate.tenant is not null and coalesce(better_supabase.can('tenant', store_agent_mandate.tenant, 'agent_checkout.write'), false))) then
    raise exception 'not allowed to store mandates' using errcode = '42501', hint = 'AGENT_MANDATE_FORBIDDEN';
  end if;
  if coalesce(v_input ->> 'vct', '') not in ('mandate.checkout.open.1', 'mandate.checkout.1') then
    raise exception 'vct is mandate.checkout.open.1 or mandate.checkout.1' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
  end if;
  if coalesce(v_input ->> 'credential', '') = '' or coalesce(v_input ->> 'credentialHash', '') = '' or coalesce(v_input ->> 'expiresAt', '') = '' then
    raise exception 'a mandate needs a credential, its hash and an expiry' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
  end if;
  v_expires := (v_input ->> 'expiresAt')::timestamptz;
  if v_expires <= now() then
    raise exception 'the mandate expired' using errcode = '22023', hint = 'AGENT_MANDATE_EXPIRED';
  end if;
  if coalesce(v_input ->> 'sessionId', '') <> '' and not exists (
    select 1 from "better_supabase"."checkout_sessions" x
    where x."id" = (v_input ->> 'sessionId')::uuid and x."org_id" = store_agent_mandate.tenant
  ) then
    raise exception 'no such checkout session' using errcode = 'P0002', hint = 'CHECKOUT_SESSION_NOT_FOUND';
  end if;
  insert into "better_supabase"."agent_mandates" ("org_id", "session_id", "vct", "credential", "credential_hash", "issuer_kid", "subject", "expires_at")
  values (store_agent_mandate.tenant, nullif(v_input ->> 'sessionId', '')::uuid, v_input ->> 'vct', v_input ->> 'credential',
    v_input ->> 'credentialHash', nullif(v_input ->> 'issuerKid', ''), nullif(v_input ->> 'subject', ''), v_expires)
  on conflict ("org_id", "credential_hash") do nothing
  returning * into v_row;
  if not found then
    select * into v_row from "better_supabase"."agent_mandates" x
    where x."org_id" = store_agent_mandate.tenant and x."credential_hash" = v_input ->> 'credentialHash';
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'sessionId', v_row."session_id", 'vct', v_row."vct", 'status', v_row."status", 'credential', v_row."credential", 'credentialHash', v_row."credential_hash", 'issuerKid', v_row."issuer_kid", 'subject', v_row."subject", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" = 'active' and v_row."expires_at" <= now()), 'consumedAt', v_row."consumed_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
  end if;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'sessionId', v_row."session_id", 'vct', v_row."vct", 'status', v_row."status", 'credential', v_row."credential", 'credentialHash', v_row."credential_hash", 'issuerKid', v_row."issuer_kid", 'subject', v_row."subject", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" = 'active' and v_row."expires_at" <= now()), 'consumedAt', v_row."consumed_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."store_agent_mandate"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."store_agent_mandate"(uuid, jsonb) to authenticated, service_role;

-- Uses a closed mandate once, for one session. An open mandate is never
-- consumed: it keeps authorizing closed ones until it expires or is revoked.
-- Needs agent_checkout.write.
create or replace function "better_supabase"."consume_agent_mandate"(mandate_id uuid, session_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."agent_mandates";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."agent_mandates" x where x."id" = consume_agent_mandate.mandate_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'agent_checkout.read'), false))) then
    raise exception 'no such mandate' using errcode = 'P0002', hint = 'AGENT_MANDATE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'agent_checkout.write'), false))) then
    raise exception 'not allowed to use mandates' using errcode = '42501', hint = 'AGENT_MANDATE_FORBIDDEN';
  end if;
  if v_row."vct" <> 'mandate.checkout.1' then
    raise exception 'only a closed mandate is consumed' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
  end if;
  if v_row."status" <> 'active' then
    raise exception 'the mandate was already used or revoked' using errcode = '55000', hint = 'AGENT_MANDATE_USED';
  end if;
  if v_row."expires_at" <= now() then
    raise exception 'the mandate expired' using errcode = '55000', hint = 'AGENT_MANDATE_EXPIRED';
  end if;
  if v_row."session_id" is not null and v_row."session_id" <> consume_agent_mandate.session_id then
    raise exception 'the mandate belongs to another session' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
  end if;
  update "better_supabase"."agent_mandates" x set "status" = 'consumed', "consumed_at" = now(), "session_id" = coalesce(x."session_id", consume_agent_mandate.session_id)
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'sessionId', v_row."session_id", 'vct', v_row."vct", 'status', v_row."status", 'credential', v_row."credential", 'credentialHash', v_row."credential_hash", 'issuerKid', v_row."issuer_kid", 'subject', v_row."subject", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" = 'active' and v_row."expires_at" <= now()), 'consumedAt', v_row."consumed_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."consume_agent_mandate"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."consume_agent_mandate"(uuid, uuid) to authenticated, service_role;

-- Revokes an active mandate; false when it was not active. Needs
-- agent_checkout.manage.
create or replace function "better_supabase"."revoke_agent_mandate"(mandate_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."agent_mandates";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."agent_mandates" x where x."id" = revoke_agent_mandate.mandate_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'agent_checkout.read'), false))) then
    raise exception 'no such mandate' using errcode = 'P0002', hint = 'AGENT_MANDATE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'agent_checkout.manage'), false))) then
    raise exception 'not allowed to revoke mandates' using errcode = '42501', hint = 'AGENT_MANDATE_FORBIDDEN';
  end if;
  if v_row."status" <> 'active' then
    return false;
  end if;
  update "better_supabase"."agent_mandates" x set "status" = 'revoked' where x."id" = v_row."id" returning * into v_row;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."revoke_agent_mandate"(uuid) from public, anon;
grant execute on function "better_supabase"."revoke_agent_mandate"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."get_agent_mandate"(mandate_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."agent_mandates";
begin
  select * into v_row from "better_supabase"."agent_mandates" x where x."id" = get_agent_mandate.mandate_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'agent_checkout.read'), false))) then
    raise exception 'no such mandate' using errcode = 'P0002', hint = 'AGENT_MANDATE_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'sessionId', v_row."session_id", 'vct', v_row."vct", 'status', v_row."status", 'credential', v_row."credential", 'credentialHash', v_row."credential_hash", 'issuerKid', v_row."issuer_kid", 'subject', v_row."subject", 'expiresAt', v_row."expires_at", 'expired', (v_row."status" = 'active' and v_row."expires_at" <= now()), 'consumedAt', v_row."consumed_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."get_agent_mandate"(uuid) from public, anon;
grant execute on function "better_supabase"."get_agent_mandate"(uuid) to authenticated, service_role;

-- Mandates, newest first. filters is { sessionId, status, vct, limit, offset }.
create or replace function "better_supabase"."list_agent_mandates"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_agent_mandates.filters, '{}'::jsonb);
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_agent_mandates.tenant is not null and coalesce(better_supabase.can('tenant', list_agent_mandates.tenant, 'agent_checkout.read'), false))) then
    raise exception 'not allowed to read mandates' using errcode = '42501', hint = 'AGENT_MANDATE_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."org_id", 'sessionId', y."session_id", 'vct', y."vct", 'status', y."status", 'credential', y."credential", 'credentialHash', y."credential_hash", 'issuerKid', y."issuer_kid", 'subject', y."subject", 'expiresAt', y."expires_at", 'expired', (y."status" = 'active' and y."expires_at" <= now()), 'consumedAt', y."consumed_at", 'createdBy', y."created_by", 'createdAt', y."created_at") order by y."created_at" desc, y."id")
    from (
      select * from "better_supabase"."agent_mandates" x
      where x."org_id" = list_agent_mandates.tenant
        and (not v_filters ? 'sessionId' or x."session_id"::text = v_filters ->> 'sessionId')
        and (not v_filters ? 'status' or x."status" = v_filters ->> 'status')
        and (not v_filters ? 'vct' or x."vct" = v_filters ->> 'vct')
      order by x."created_at" desc, x."id"
      limit v_limit offset coalesce((v_filters ->> 'offset')::integer, 0)
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_agent_mandates"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_agent_mandates"(uuid, jsonb) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."checkout_sessions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."checkout_sessions";
create policy bsb_tenant_scope_select on "better_supabase"."checkout_sessions" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('agent_checkout.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."checkout_sessions";
create policy bsb_tenant_scope_insert on "better_supabase"."checkout_sessions" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."checkout_sessions";
create policy bsb_tenant_scope_update on "better_supabase"."checkout_sessions" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."checkout_sessions";
create policy bsb_tenant_scope_delete on "better_supabase"."checkout_sessions" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."agent_mandates";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."agent_mandates";
create policy bsb_tenant_scope_select on "better_supabase"."agent_mandates" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('agent_checkout.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."agent_mandates";
create policy bsb_tenant_scope_insert on "better_supabase"."agent_mandates" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."agent_mandates";
create policy bsb_tenant_scope_update on "better_supabase"."agent_mandates" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."agent_mandates";
create policy bsb_tenant_scope_delete on "better_supabase"."agent_mandates" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));

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
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_171_agent_checkout.sql
-- better-supabase module: agent-checkout
-- @bsb-block-data agent-checkout
-- @bsb-hash sha256:f2ff7f54e754107be5e7c58c415111abecc80d24eacb7640b39ab53ea8c96238
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('agent-checkout', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
