-- ==== schema supabase/schemas/900_better_supabase_179_agent_checkout.sql
-- better-supabase module: agent-checkout
-- @bsb-block agent-checkout@1 managed
-- @bsb-hash sha256:a02034833cf99c6baabc0c69abb8cebefebdb9b940a9935f9eccd7f2d891049a
-- ACP and UCP checkout sessions over an orders cart with idempotency keys, and AP2 checkout mandates verified with signing keys and used once.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Agent checkout: ACP and UCP checkout sessions over an orders cart, and AP2
-- mandates stored beside them. The session keeps the protocol state; the cart
-- and the order keep the money (bigint minor units).
create table "better_supabase"."checkout_sessions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "cart_id" uuid not null,
  "protocol" text not null constraint bsb_checkout_sessions_protocol_check check ("protocol" in ('acp', 'ucp')),
  "status" text not null default 'open' constraint bsb_checkout_sessions_status_check check ("status" in ('open', 'ready', 'completed', 'canceled')),
  "idempotency_key" text not null constraint bsb_checkout_sessions_idempotency_key_check check (length("idempotency_key") >= 1 and length("idempotency_key") <= 255),
  "request_hash" text not null constraint bsb_checkout_sessions_request_hash_check check (length("request_hash") >= 1 and length("request_hash") <= 128),
  "buyer" jsonb,
  "order_id" uuid,
  "expires_at" timestamptz,
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "idempotency_key"),
  constraint bsb_checkout_sessions_check check (("status" = 'completed') = ("order_id" is not null))
);
create index "checkout_sessions_cart_idx" on "better_supabase"."checkout_sessions" ("cart_id");
alter table "better_supabase"."checkout_sessions" enable row level security;
revoke all on "better_supabase"."checkout_sessions" from public, anon, authenticated;
grant select on "better_supabase"."checkout_sessions" to authenticated;
grant all on "better_supabase"."checkout_sessions" to service_role;
create policy bsb_checkout_sessions_read on "better_supabase"."checkout_sessions"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('agent_checkout.read')));

-- A mandate an agent presents: the compact credential, its hash and the key
-- that signed it. The TypeScript side verifies the signature with the
-- signing-keys block before it stores the row; closed mandates are used once.
create table "better_supabase"."agent_mandates" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "session_id" uuid references "better_supabase"."checkout_sessions" ("id") on delete set null,
  "vct" text not null constraint bsb_agent_mandates_vct_check check ("vct" in ('mandate.checkout.open.1', 'mandate.checkout.1')),
  "status" text not null default 'active' constraint bsb_agent_mandates_status_check check ("status" in ('active', 'consumed', 'revoked')),
  "credential" text not null constraint bsb_agent_mandates_credential_check check (length("credential") >= 1 and length("credential") <= 16384),
  "credential_hash" text not null constraint bsb_agent_mandates_credential_hash_check check (length("credential_hash") >= 1 and length("credential_hash") <= 128),
  "issuer_kid" text,
  "subject" text,
  "expires_at" timestamptz not null,
  "consumed_at" timestamptz,
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "credential_hash"),
  constraint bsb_agent_mandates_check check (("status" = 'consumed') = ("consumed_at" is not null))
);
create index "agent_mandates_session_idx" on "better_supabase"."agent_mandates" ("session_id");
alter table "better_supabase"."agent_mandates" enable row level security;
revoke all on "better_supabase"."agent_mandates" from public, anon, authenticated;
grant select on "better_supabase"."agent_mandates" to authenticated;
grant all on "better_supabase"."agent_mandates" to service_role;
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
create policy bsb_tenant_scope_select on "better_supabase"."checkout_sessions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('agent_checkout.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."checkout_sessions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."checkout_sessions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."checkout_sessions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."agent_mandates" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('agent_checkout.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."agent_mandates" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."agent_mandates" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."agent_mandates" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));

-- ==== data supabase/better-supabase-data/900_better_supabase_179_agent_checkout.sql
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
