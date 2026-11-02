import type { AgentCheckoutEvents } from "../../blocks/agent-checkout/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  fail,
  lockTable,
  pageSize,
  schemaPreamble,
  SERVICE_CALLER,
  serviceGrant,
  userGrant,
} from "../shared.ts";
import {
  AGENT_MANDATE_STATUSES,
  AGENT_MANDATE_TYPES,
  CHECKOUT_PROTOCOLS,
  CHECKOUT_SESSION_STATUSES,
} from "./agent-checkout-values.ts";
import { OPERATIONS } from "./permissions-model.ts";

const session = {
  subject: "checkout-sessions",
  payload: ["organizationId", "id", "cartId", "protocol", "status"],
} as const;

const mandate = {
  subject: "agent-mandates",
  payload: ["organizationId", "id", "vct", "sessionId"],
} as const;

const EVENTS: BlockSqlEvents<AgentCheckoutEvents> = {
  "checkout_session.created": session,
  "checkout_session.updated": session,
  "checkout_session.completed": {
    subject: "checkout-sessions",
    payload: [
      "organizationId",
      "id",
      "cartId",
      "protocol",
      "status",
      "orderId",
    ],
  },
  "agent_mandate.created": mandate,
  "agent_mandate.consumed": mandate,
  "agent_mandate.revoked": mandate,
};

const NAMES: BlockSqlNames = {
  entities: {
    checkout_session: {
      table: "sessions",
      singular: "checkout_session",
      primary: true,
    },
    agent_mandate: { table: "mandates", singular: "agent_mandate" },
  },
  events: EVENTS,
  options: [],
  tables: {
    sessions: {
      name: "checkout_sessions",
      app: {},
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        cart: "cart_id",
        protocol: "protocol",
        status: "status",
        idempotencyKey: "idempotency_key",
        requestHash: "request_hash",
        buyer: "buyer",
        order: "order_id",
        expiresAt: "expires_at",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    mandates: {
      name: "agent_mandates",
      app: {},
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        session: "session_id",
        vct: "vct",
        status: "status",
        credential: "credential",
        credentialHash: "credential_hash",
        issuerKid: "issuer_kid",
        subject: "subject",
        expiresAt: "expires_at",
        consumedAt: "consumed_at",
        createdBy: "created_by",
        createdAt: "created_at",
      },
    },
  },
};

const list = (values: readonly string[]): string =>
  values.map((value) => sqlString(value)).join(", ");

/** A block context of another module, when it is installed and not custom. */
function linked(
  ctx: BlockSqlContext,
  module: string,
): BlockSqlContext | undefined {
  return ctx.installed(module) && ctx.of(module).mode !== "custom"
    ? ctx.of(module)
    : undefined;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const fn = (name: string): string => ctx.fn(name);
  const id = ctx.idType;
  const s = (c: string): string => ctx.col("sessions", c);
  const m = (c: string): string => ctx.col("mandates", c);
  const sessions = ctx.table("sessions");
  const mandates = ctx.table("mandates");
  const orders = linked(ctx, "orders");
  const read = ctx.permission("read", OPERATIONS["agent-checkout.read"]);
  const write = ctx.permission("write", OPERATIONS["agent-checkout.write"]);
  const manage = ctx.permission("manage", OPERATIONS["agent-checkout.manage"]);

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or (${tenant} is not null and ${ctx.can("tenant", tenant, permission)}))`;

  const name = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  const appKey = (logical: string, what: string, columns: string): string =>
    ctx.owns(logical)
      ? ""
      : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName(logical).name}_${what}_key`)} on ${ctx.table(logical)} (${columns});`;

  const readPolicy = (logical: string, tenant: string): string =>
    renderPolicy(
      makePolicy({
        table: ctx.table(logical),
        name: ctx.owns(logical)
          ? name(logical, "read")
          : sqlIdent(`bsb_${ctx.tableName(logical).name}_read`),
        command: "select",
        roles: ["authenticated"],
        using: ctx.scope.check(tenant, read),
      }),
      { drop: true, target: ctx.table(logical) },
    );

  const invalid = (message: string): string =>
    fail("CHECKOUT_INVALID", message, "22023");

  const sessionJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${s("id")}, 'organizationId', ${row}.${s("tenant")}, 'cartId', ${row}.${s("cart")}, 'protocol', ${row}.${s("protocol")}, 'status', ${row}.${s("status")}, 'buyer', ${row}.${s("buyer")}, 'orderId', ${row}.${s("order")}, 'expiresAt', ${row}.${s("expiresAt")}, 'expired', (${row}.${s("status")} in ('open', 'ready') and ${row}.${s("expiresAt")} is not null and ${row}.${s("expiresAt")} <= now()), 'createdBy', ${row}.${s("createdBy")}, 'createdAt', ${row}.${s("createdAt")}, 'updatedAt', ${row}.${s("updatedAt")})`;

  const mandateJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${m("id")}, 'organizationId', ${row}.${m("tenant")}, 'sessionId', ${row}.${m("session")}, 'vct', ${row}.${m("vct")}, 'status', ${row}.${m("status")}, 'credential', ${row}.${m("credential")}, 'credentialHash', ${row}.${m("credentialHash")}, 'issuerKid', ${row}.${m("issuerKid")}, 'subject', ${row}.${m("subject")}, 'expiresAt', ${row}.${m("expiresAt")}, 'expired', (${row}.${m("status")} = 'active' and ${row}.${m("expiresAt")} <= now()), 'consumedAt', ${row}.${m("consumedAt")}, 'createdBy', ${row}.${m("createdBy")}, 'createdAt', ${row}.${m("createdAt")})`;

  const recordSession = (type: string, row: string, summary: string): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', ${row}.${s("tenant")}, 'id', ${row}.${s("id")}, 'cartId', ${row}.${s("cart")}, 'protocol', ${row}.${s("protocol")}, 'status', ${row}.${s("status")}${type === "checkout_session.completed" ? `, 'orderId', ${row}.${s("order")}` : ""})`,
      subject: `'checkout-sessions/' || ${row}.${s("id")}::text`,
      tenant: `${row}.${s("tenant")}`,
      key: `${sqlString(`${type}:`)} || ${row}.${s("id")}::text || ':' || ${row}.${s("status")}`,
      audit: {
        category: "data",
        targetType: "checkout_session",
        recordId: `${row}.${s("id")}::text`,
        summary: sqlString(summary),
      },
    });

  const recordMandate = (type: string, row: string, summary: string): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', ${row}.${m("tenant")}, 'id', ${row}.${m("id")}, 'vct', ${row}.${m("vct")}, 'sessionId', ${row}.${m("session")})`,
      subject: `'agent-mandates/' || ${row}.${m("id")}::text`,
      tenant: `${row}.${m("tenant")}`,
      audit: {
        category: "security",
        targetType: "agent_mandate",
        recordId: `${row}.${m("id")}::text`,
        summary: sqlString(summary),
      },
    });

  // With orders installed, a cart must be the caller's own in the tenant, and
  // a completed order must be the one the cart became.
  const cartCheck = orders
    ? `
  if not exists (
    select 1 from ${orders.table("carts")} c
    where c.${orders.col("carts", "id")} = create_checkout_session.cart_id
      and c.${orders.col("carts", "tenant")} = create_checkout_session.tenant
      and (${SERVICE_CALLER} or c.${orders.col("carts", "user")} = auth.uid())
  ) then
    ${fail("CHECKOUT_CART_NOT_FOUND", "no such cart", "P0002")}
  end if;`
    : "";

  const orderCheck = orders
    ? `
  if not exists (
    select 1 from ${orders.table("orders")} o
    where o.${orders.col("orders", "id")} = complete_checkout_session.order_id
      and o.${orders.col("orders", "cart")} = v_row.${s("cart")}
      and o.${orders.col("orders", "tenant")} = v_row.${s("tenant")}
  ) then
    ${invalid("the order is not the one placed from the session's cart")}
  end if;`
    : "";

  return `${schemaPreamble(ctx)}
-- Agent checkout: ACP and UCP checkout sessions over an orders cart, and AP2
-- mandates stored beside them. The session keeps the protocol state; the cart
-- and the order keep the money (bigint minor units).
create table if not exists ${sessions} (
  ${s("id")} uuid primary key default gen_random_uuid(),
  ${s("tenant")} ${id} not null,
  ${s("cart")} uuid not null,
  ${s("protocol")} text not null check (${s("protocol")} in (${list(CHECKOUT_PROTOCOLS)})),
  ${s("status")} text not null default 'open' check (${s("status")} in (${list(CHECKOUT_SESSION_STATUSES)})),
  ${s("idempotencyKey")} text not null check (length(${s("idempotencyKey")}) between 1 and 255),
  ${s("requestHash")} text not null check (length(${s("requestHash")}) between 1 and 128),
  ${s("buyer")} jsonb,
  ${s("order")} uuid,
  ${s("expiresAt")} timestamptz,
  ${s("createdBy")} uuid default auth.uid(),
  ${s("createdAt")} timestamptz not null default now(),
  ${s("updatedAt")} timestamptz not null default now(),
  unique (${s("tenant")}, ${s("idempotencyKey")}),
  check ((${s("status")} = 'completed') = (${s("order")} is not null))
);${appKey("sessions", "tenant_id", `${s("tenant")}, ${s("id")}`)}
create index if not exists ${name("sessions", "cart_idx")} on ${sessions} (${s("cart")});
${lockTable(sessions, { read: true })}
${readPolicy("sessions", s("tenant"))}

-- A mandate an agent presents: the compact credential, its hash and the key
-- that signed it. The TypeScript side verifies the signature with the
-- signing-keys block before it stores the row; closed mandates are used once.
create table if not exists ${mandates} (
  ${m("id")} uuid primary key default gen_random_uuid(),
  ${m("tenant")} ${id} not null,
  ${m("session")} uuid${ctx.owns("sessions") ? ` references ${sessions} (${s("id")}) on delete set null` : ""},
  ${m("vct")} text not null check (${m("vct")} in (${list(AGENT_MANDATE_TYPES)})),
  ${m("status")} text not null default 'active' check (${m("status")} in (${list(AGENT_MANDATE_STATUSES)})),
  ${m("credential")} text not null check (length(${m("credential")}) between 1 and 16384),
  ${m("credentialHash")} text not null check (length(${m("credentialHash")}) between 1 and 128),
  ${m("issuerKid")} text,
  ${m("subject")} text,
  ${m("expiresAt")} timestamptz not null,
  ${m("consumedAt")} timestamptz,
  ${m("createdBy")} uuid default auth.uid(),
  ${m("createdAt")} timestamptz not null default now(),
  unique (${m("tenant")}, ${m("credentialHash")}),
  check ((${m("status")} = 'consumed') = (${m("consumedAt")} is not null))
);${appKey("mandates", "tenant_id", `${m("tenant")}, ${m("id")}`)}${appKey("mandates", "tenant_credential_hash", `${m("tenant")}, ${m("credentialHash")}`)}
create index if not exists ${name("mandates", "session_idx")} on ${mandates} (${m("session")});
${lockTable(mandates, { read: true })}
${readPolicy("mandates", m("tenant"))}

-- Starts a checkout session over a cart, or returns the one this idempotency
-- key made before (replayed true). The same key with another request_hash
-- fails with CHECKOUT_IDEMPOTENCY_CONFLICT. Needs agent_checkout.write.
create or replace function ${fn("create_checkout_session")}(tenant ${id}, cart_id uuid, protocol text, idempotency_key text, request_hash text, expires_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${sessions};
begin
  if not ${allowed("create_checkout_session.tenant", write)} then
    ${fail("CHECKOUT_FORBIDDEN", "not allowed to start checkout sessions")}
  end if;
  if create_checkout_session.protocol is null or create_checkout_session.protocol not in (${list(CHECKOUT_PROTOCOLS)}) then
    ${invalid("the protocol is acp or ucp")}
  end if;
  if coalesce(create_checkout_session.idempotency_key, '') = '' or coalesce(create_checkout_session.request_hash, '') = '' then
    ${fail("CHECKOUT_IDEMPOTENCY_KEY_REQUIRED", "a checkout session needs an idempotency key", "22023")}
  end if;
  select * into v_row from ${sessions} x
  where x.${s("tenant")} = create_checkout_session.tenant and x.${s("idempotencyKey")} = create_checkout_session.idempotency_key;
  if found then
    if v_row.${s("requestHash")} <> create_checkout_session.request_hash then
      ${fail("CHECKOUT_IDEMPOTENCY_CONFLICT", "this idempotency key was used with another request", "22023")}
    end if;
    return ${sessionJson("v_row")} || jsonb_build_object('replayed', true);
  end if;${cartCheck}
  begin
    insert into ${sessions} (${s("tenant")}, ${s("cart")}, ${s("protocol")}, ${s("idempotencyKey")}, ${s("requestHash")}, ${s("expiresAt")})
    values (create_checkout_session.tenant, create_checkout_session.cart_id, create_checkout_session.protocol,
      create_checkout_session.idempotency_key, create_checkout_session.request_hash, create_checkout_session.expires_at)
    returning * into v_row;
  exception when unique_violation then
    select * into v_row from ${sessions} x
    where x.${s("tenant")} = create_checkout_session.tenant and x.${s("idempotencyKey")} = create_checkout_session.idempotency_key;
    if not found or v_row.${s("requestHash")} <> create_checkout_session.request_hash then
      ${fail("CHECKOUT_IDEMPOTENCY_CONFLICT", "this idempotency key was used with another request", "22023")}
    end if;
    return ${sessionJson("v_row")} || jsonb_build_object('replayed', true);
  end;
  ${recordSession("checkout_session.created", "v_row", "checkout session created")}
  return ${sessionJson("v_row")} || jsonb_build_object('replayed', false);
end;
$$;
${userGrant(`${fn("create_checkout_session")}(${id}, uuid, text, text, text, timestamptz)`)}

-- Changes an open session. input may hold buyer (a JSON object), status (open,
-- ready or canceled) and expiresAt. A completed or canceled session is final.
-- Needs agent_checkout.write.
create or replace function ${fn("update_checkout_session")}(session_id uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_input jsonb := coalesce(update_checkout_session.input, '{}'::jsonb);
  v_row ${sessions};
  v_status text;
begin
  select * into v_row from ${sessions} x where x.${s("id")} = update_checkout_session.session_id for update;
  if not found or not ${allowed(`v_row.${s("tenant")}`, read)} then
    ${fail("CHECKOUT_SESSION_NOT_FOUND", "no such checkout session", "P0002")}
  end if;
  if not ${allowed(`v_row.${s("tenant")}`, write)} then
    ${fail("CHECKOUT_FORBIDDEN", "not allowed to change checkout sessions")}
  end if;
  if v_row.${s("status")} not in ('open', 'ready') then
    ${fail("CHECKOUT_SESSION_FINAL", "the session is completed or canceled", "55000")}
  end if;
  if v_row.${s("expiresAt")} is not null and v_row.${s("expiresAt")} <= now() then
    ${fail("CHECKOUT_SESSION_EXPIRED", "the session expired", "55000")}
  end if;
  v_status := coalesce(v_input ->> 'status', v_row.${s("status")});
  if v_status not in ('open', 'ready', 'canceled') then
    ${invalid("status is open, ready or canceled")}
  end if;
  if v_input ? 'buyer' and jsonb_typeof(v_input -> 'buyer') not in ('object', 'null') then
    ${invalid("buyer is an object or null")}
  end if;
  update ${sessions} x set
    ${s("status")} = v_status,
    ${s("buyer")} = case when v_input ? 'buyer' then nullif(v_input -> 'buyer', 'null'::jsonb) else x.${s("buyer")} end,
    ${s("expiresAt")} = case when v_input ? 'expiresAt' then (v_input ->> 'expiresAt')::timestamptz else x.${s("expiresAt")} end,
    ${s("updatedAt")} = now()
  where x.${s("id")} = v_row.${s("id")}
  returning * into v_row;
  ${recordSession("checkout_session.updated", "v_row", "checkout session changed")}
  return ${sessionJson("v_row")};
end;
$$;
${userGrant(`${fn("update_checkout_session")}(uuid, jsonb)`)}

create or replace function ${fn("get_checkout_session")}(session_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${sessions};
begin
  select * into v_row from ${sessions} x where x.${s("id")} = get_checkout_session.session_id;
  if not found or not ${allowed(`v_row.${s("tenant")}`, read)} then
    ${fail("CHECKOUT_SESSION_NOT_FOUND", "no such checkout session", "P0002")}
  end if;
  return ${sessionJson("v_row")};
end;
$$;
${userGrant(`${fn("get_checkout_session")}(uuid)`)}

-- Sessions, newest first. filters is { status, protocol, cartId, limit, offset }.
create or replace function ${fn("list_checkout_sessions")}(tenant ${id}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_checkout_sessions.filters, '{}'::jsonb);
  v_limit integer := ${pageSize("(v_filters ->> 'limit')::integer", 50, 200)};
begin
  if not ${allowed("list_checkout_sessions.tenant", read)} then
    ${fail("CHECKOUT_FORBIDDEN", "not allowed to read checkout sessions")}
  end if;
  return coalesce((
    select jsonb_agg(${sessionJson("y")} order by y.${s("createdAt")} desc, y.${s("id")})
    from (
      select * from ${sessions} x
      where x.${s("tenant")} = list_checkout_sessions.tenant
        and (not v_filters ? 'status' or x.${s("status")} = v_filters ->> 'status')
        and (not v_filters ? 'protocol' or x.${s("protocol")} = v_filters ->> 'protocol')
        and (not v_filters ? 'cartId' or x.${s("cart")}::text = v_filters ->> 'cartId')
      order by x.${s("createdAt")} desc, x.${s("id")}
      limit v_limit offset coalesce((v_filters ->> 'offset')::integer, 0)
    ) y
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_checkout_sessions")}(${id}, jsonb)`)}

-- Marks a session completed with the order its cart became. Service only: the
-- TypeScript side calls it after the orders checkout placed the order and took
-- the payment through the payment provider. Completing again with the same
-- order returns the session.
create or replace function ${fn("complete_checkout_session")}(session_id uuid, order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${sessions};
begin
  if not ${SERVICE_CALLER} then
    ${fail("CHECKOUT_FORBIDDEN", "only the service role completes checkout sessions")}
  end if;
  select * into v_row from ${sessions} x where x.${s("id")} = complete_checkout_session.session_id for update;
  if not found then
    ${fail("CHECKOUT_SESSION_NOT_FOUND", "no such checkout session", "P0002")}
  end if;
  if v_row.${s("status")} = 'completed' then
    if v_row.${s("order")} = complete_checkout_session.order_id then
      return ${sessionJson("v_row")};
    end if;
    ${fail("CHECKOUT_SESSION_FINAL", "the session completed with another order", "55000")}
  end if;
  if v_row.${s("status")} = 'canceled' then
    ${fail("CHECKOUT_SESSION_FINAL", "the session is canceled", "55000")}
  end if;
  if complete_checkout_session.order_id is null then
    ${invalid("order_id is required")}
  end if;${orderCheck}
  update ${sessions} x set ${s("status")} = 'completed', ${s("order")} = complete_checkout_session.order_id, ${s("updatedAt")} = now()
  where x.${s("id")} = v_row.${s("id")}
  returning * into v_row;
  ${recordSession("checkout_session.completed", "v_row", "checkout session completed")}
  return ${sessionJson("v_row")};
end;
$$;
${serviceGrant(`${fn("complete_checkout_session")}(uuid, uuid)`)}

-- Stores a verified mandate. input is { vct, credential, credentialHash,
-- issuerKid, subject, expiresAt, sessionId }. Storing the same credential
-- again returns the stored row. Needs agent_checkout.write.
create or replace function ${fn("store_agent_mandate")}(tenant ${id}, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_input jsonb := coalesce(store_agent_mandate.input, '{}'::jsonb);
  v_row ${mandates};
  v_expires timestamptz;
begin
  if not ${allowed("store_agent_mandate.tenant", write)} then
    ${fail("AGENT_MANDATE_FORBIDDEN", "not allowed to store mandates")}
  end if;
  if coalesce(v_input ->> 'vct', '') not in (${list(AGENT_MANDATE_TYPES)}) then
    ${fail("AGENT_MANDATE_INVALID", "vct is mandate.checkout.open.1 or mandate.checkout.1", "22023")}
  end if;
  if coalesce(v_input ->> 'credential', '') = '' or coalesce(v_input ->> 'credentialHash', '') = '' or coalesce(v_input ->> 'expiresAt', '') = '' then
    ${fail("AGENT_MANDATE_INVALID", "a mandate needs a credential, its hash and an expiry", "22023")}
  end if;
  v_expires := (v_input ->> 'expiresAt')::timestamptz;
  if v_expires <= now() then
    ${fail("AGENT_MANDATE_EXPIRED", "the mandate expired", "22023")}
  end if;
  if coalesce(v_input ->> 'sessionId', '') <> '' and not exists (
    select 1 from ${sessions} x
    where x.${s("id")} = (v_input ->> 'sessionId')::uuid and x.${s("tenant")} = store_agent_mandate.tenant
  ) then
    ${fail("CHECKOUT_SESSION_NOT_FOUND", "no such checkout session", "P0002")}
  end if;
  insert into ${mandates} (${m("tenant")}, ${m("session")}, ${m("vct")}, ${m("credential")}, ${m("credentialHash")}, ${m("issuerKid")}, ${m("subject")}, ${m("expiresAt")})
  values (store_agent_mandate.tenant, nullif(v_input ->> 'sessionId', '')::uuid, v_input ->> 'vct', v_input ->> 'credential',
    v_input ->> 'credentialHash', nullif(v_input ->> 'issuerKid', ''), nullif(v_input ->> 'subject', ''), v_expires)
  on conflict (${m("tenant")}, ${m("credentialHash")}) do nothing
  returning * into v_row;
  if not found then
    select * into v_row from ${mandates} x
    where x.${m("tenant")} = store_agent_mandate.tenant and x.${m("credentialHash")} = v_input ->> 'credentialHash';
    return ${mandateJson("v_row")};
  end if;
  ${recordMandate("agent_mandate.created", "v_row", "agent mandate stored")}
  return ${mandateJson("v_row")};
end;
$$;
${userGrant(`${fn("store_agent_mandate")}(${id}, jsonb)`)}

-- Uses a closed mandate once, for one session. An open mandate is never
-- consumed: it keeps authorizing closed ones until it expires or is revoked.
-- Needs agent_checkout.write.
create or replace function ${fn("consume_agent_mandate")}(mandate_id uuid, session_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${mandates};
begin
  select * into v_row from ${mandates} x where x.${m("id")} = consume_agent_mandate.mandate_id for update;
  if not found or not ${allowed(`v_row.${m("tenant")}`, read)} then
    ${fail("AGENT_MANDATE_NOT_FOUND", "no such mandate", "P0002")}
  end if;
  if not ${allowed(`v_row.${m("tenant")}`, write)} then
    ${fail("AGENT_MANDATE_FORBIDDEN", "not allowed to use mandates")}
  end if;
  if v_row.${m("vct")} <> 'mandate.checkout.1' then
    ${fail("AGENT_MANDATE_INVALID", "only a closed mandate is consumed", "22023")}
  end if;
  if v_row.${m("status")} <> 'active' then
    ${fail("AGENT_MANDATE_USED", "the mandate was already used or revoked", "55000")}
  end if;
  if v_row.${m("expiresAt")} <= now() then
    ${fail("AGENT_MANDATE_EXPIRED", "the mandate expired", "55000")}
  end if;
  if v_row.${m("session")} is not null and v_row.${m("session")} <> consume_agent_mandate.session_id then
    ${fail("AGENT_MANDATE_INVALID", "the mandate belongs to another session", "22023")}
  end if;
  update ${mandates} x set ${m("status")} = 'consumed', ${m("consumedAt")} = now(), ${m("session")} = coalesce(x.${m("session")}, consume_agent_mandate.session_id)
  where x.${m("id")} = v_row.${m("id")}
  returning * into v_row;
  ${recordMandate("agent_mandate.consumed", "v_row", "agent mandate used")}
  return ${mandateJson("v_row")};
end;
$$;
${userGrant(`${fn("consume_agent_mandate")}(uuid, uuid)`)}

-- Revokes an active mandate; false when it was not active. Needs
-- agent_checkout.manage.
create or replace function ${fn("revoke_agent_mandate")}(mandate_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${mandates};
begin
  select * into v_row from ${mandates} x where x.${m("id")} = revoke_agent_mandate.mandate_id for update;
  if not found or not ${allowed(`v_row.${m("tenant")}`, read)} then
    ${fail("AGENT_MANDATE_NOT_FOUND", "no such mandate", "P0002")}
  end if;
  if not ${allowed(`v_row.${m("tenant")}`, manage)} then
    ${fail("AGENT_MANDATE_FORBIDDEN", "not allowed to revoke mandates")}
  end if;
  if v_row.${m("status")} <> 'active' then
    return false;
  end if;
  update ${mandates} x set ${m("status")} = 'revoked' where x.${m("id")} = v_row.${m("id")} returning * into v_row;
  ${recordMandate("agent_mandate.revoked", "v_row", "agent mandate revoked")}
  return true;
end;
$$;
${userGrant(`${fn("revoke_agent_mandate")}(uuid)`)}

create or replace function ${fn("get_agent_mandate")}(mandate_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${mandates};
begin
  select * into v_row from ${mandates} x where x.${m("id")} = get_agent_mandate.mandate_id;
  if not found or not ${allowed(`v_row.${m("tenant")}`, read)} then
    ${fail("AGENT_MANDATE_NOT_FOUND", "no such mandate", "P0002")}
  end if;
  return ${mandateJson("v_row")};
end;
$$;
${userGrant(`${fn("get_agent_mandate")}(uuid)`)}

-- Mandates, newest first. filters is { sessionId, status, vct, limit, offset }.
create or replace function ${fn("list_agent_mandates")}(tenant ${id}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_agent_mandates.filters, '{}'::jsonb);
  v_limit integer := ${pageSize("(v_filters ->> 'limit')::integer", 50, 200)};
begin
  if not ${allowed("list_agent_mandates.tenant", read)} then
    ${fail("AGENT_MANDATE_FORBIDDEN", "not allowed to read mandates")}
  end if;
  return coalesce((
    select jsonb_agg(${mandateJson("y")} order by y.${m("createdAt")} desc, y.${m("id")})
    from (
      select * from ${mandates} x
      where x.${m("tenant")} = list_agent_mandates.tenant
        and (not v_filters ? 'sessionId' or x.${m("session")}::text = v_filters ->> 'sessionId')
        and (not v_filters ? 'status' or x.${m("status")} = v_filters ->> 'status')
        and (not v_filters ? 'vct' or x.${m("vct")} = v_filters ->> 'vct')
      order by x.${m("createdAt")} desc, x.${m("id")}
      limit v_limit offset coalesce((v_filters ->> 'offset')::integer, 0)
    ) y
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_agent_mandates")}(${id}, jsonb)`)}
`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "create_checkout_session",
      args: ["{id}", "uuid", "text", "text", "text", "timestamptz"],
      returns: "jsonb",
    },
    {
      name: "update_checkout_session",
      args: ["uuid", "jsonb"],
      returns: "jsonb",
    },
    { name: "get_checkout_session", args: ["uuid"], returns: "jsonb" },
    {
      name: "list_checkout_sessions",
      args: ["{id}", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "complete_checkout_session",
      args: ["uuid", "uuid"],
      returns: "jsonb",
    },
    { name: "store_agent_mandate", args: ["{id}", "jsonb"], returns: "jsonb" },
    { name: "consume_agent_mandate", args: ["uuid", "uuid"], returns: "jsonb" },
    { name: "revoke_agent_mandate", args: ["uuid"], returns: "boolean" },
    { name: "get_agent_mandate", args: ["uuid"], returns: "jsonb" },
    { name: "list_agent_mandates", args: ["{id}", "jsonb"], returns: "jsonb" },
  ];
}

export const AGENT_CHECKOUT: BlockSqlDefinition = {
  name: "agent-checkout",
  scopes: ["tenant"],
  title: "Agent checkout",
  description:
    "ACP and UCP checkout sessions over an orders cart with idempotency keys, and AP2 checkout mandates verified with signing keys and used once.",
  requires: ["memberships", "permissions"],
  integrates: ["orders", "outbox", "audit"],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
};
