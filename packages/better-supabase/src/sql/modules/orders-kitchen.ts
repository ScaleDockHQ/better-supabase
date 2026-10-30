import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";
import type { OrdersNames } from "./orders-shared.ts";

import { sqlString, sqlIdent } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { fail, pageSize, userGrant } from "../shared.ts";
import { columns, orderFields, orderPayload } from "./orders-shared.ts";
import { appUniqueIndex, asText, lockModuleTable } from "./over-app.ts";

/** A line's preparation states, in kitchen order. */
const PREPARATION_STATES = ["queued", "preparing", "ready", "served"] as const;

/** The Realtime topic prefix; members join `kitchen:{organizationId}`. */
export const KITCHEN_TOPIC = "kitchen";

/** The tables `options.kitchen` adds, for the module's names. */
export const KITCHEN_TABLES = {
  kitchenStations: {
    name: "order_kitchen_stations",
    app: {},
    columns: {
      id: "id",
      tenant: "tenant_id",
      key: "key",
      name: "name",
      position: "position",
      isDefault: "is_default",
      active: "active",
      createdAt: "created_at",
      updatedAt: "updated_at",
    },
  },
  kitchenRoutes: {
    name: "order_kitchen_routes",
    app: {},
    columns: {
      product: "product_id",
      tenant: "tenant_id",
      station: "station_id",
    },
  },
  preparations: {
    name: "order_line_preparations",
    app: {},
    columns: {
      line: "order_line_id",
      tenant: "tenant_id",
      order: "order_id",
      station: "station_id",
      state: "state",
      note: "note",
      queuedAt: "queued_at",
      startedAt: "started_at",
      readyAt: "ready_at",
      servedAt: "served_at",
      updatedAt: "updated_at",
      updatedBy: "updated_by",
    },
    optional: ["note", "updatedBy"],
    typed: ["state"],
  },
} as const;

/** Whether `blocks.orders.options.kitchen` is on. */
export const kitchenOn = (ctx: BlockSqlContext): boolean =>
  ctx.flag("kitchen", false);

const STATES = `array[${PREPARATION_STATES.map(sqlString).join(", ")}]`;

const rank = (state: string): string => `array_position(${STATES}, ${state})`;

/** Lines of an order sent to the kitchen. */
const PREPARATIONS = "preparations";

/**
 * Kitchen stations, line preparation states and the reads a kitchen display and
 * an order-state board need. Changes broadcast on `kitchen:{tenant}`.
 */
export function kitchenSql(ctx: BlockSqlContext, names: OrdersNames): string {
  const catalog = ctx.of("catalog");
  const fn = (name: string): string => ctx.fn(name);
  const t = (name: string): string => ctx.table(name);
  const o = columns(ctx, "orders");
  const ol = columns(ctx, "orderLines");
  const ks = columns(ctx, "kitchenStations");
  const kr = columns(ctx, "kitchenRoutes");
  const lp = columns(ctx, "preparations");
  const products = `${catalog.table("products")} (${catalog.col("products", "id")})`;
  const { scope, manage, read, prepare } = names;
  const has = (column: string): boolean => ctx.has(PREPARATIONS, column);

  const stateOf = (alias: string): string =>
    asText(ctx, PREPARATIONS, `${alias}.${lp("state")}`);

  const note = (alias: string): string =>
    has("note") ? `${alias}.${lp("note")}` : "null::text";

  const readable = (column: string): string =>
    `${column} in (select ${scope.ids(read)}) or ${column} in (select ${scope.ids(prepare)})`;

  const policy = (table: string): string =>
    renderPolicy(
      makePolicy({
        table: t(table),
        name: `${ctx.tableName(table).name}_read`,
        command: "select",
        roles: ["authenticated"],
        using: readable(ctx.col(table, "tenant")),
      }),
      { drop: true, target: t(table) },
    );

  const guard = (tenant: string, permissions: readonly string[]): string =>
    `if not (auth.role() = 'service_role' or ${permissions.map((permission) => scope.can(tenant, permission)).join(" or ")}) then
    ${fail("ORDERS_FORBIDDEN", "not allowed to run this kitchen")}
  end if;`;

  const stationJson = (alias: string): string =>
    `jsonb_build_object('id', ${alias}.${ks("id")}, 'organizationId', ${alias}.${ks("tenant")}, 'key', ${alias}.${ks("key")}, 'name', ${alias}.${ks("name")}, 'position', ${alias}.${ks("position")}, 'isDefault', ${alias}.${ks("isDefault")}, 'active', ${alias}.${ks("active")}, 'productIds', coalesce((select jsonb_agg(r.${kr("product")} order by r.${kr("product")}) from ${t("kitchenRoutes")} r where r.${kr("station")} = ${alias}.${ks("id")}), '[]'::jsonb), 'createdAt', ${alias}.${ks("createdAt")}, 'updatedAt', ${alias}.${ks("updatedAt")})`;

  const lineJson = (prep: string, line: string): string =>
    `jsonb_build_object('lineId', ${prep}.${lp("line")}, 'orderId', ${prep}.${lp("order")}, 'stationId', ${prep}.${lp("station")}, 'title', ${line}.${ol("title")}, 'sku', ${line}.${ol("sku")}, 'quantity', ${line}.${ol("quantity")}, 'position', ${line}.${ol("position")}, 'state', ${stateOf(prep)}, 'note', ${note(prep)}, 'queuedAt', ${prep}.${lp("queuedAt")}, 'startedAt', ${prep}.${lp("startedAt")}, 'readyAt', ${prep}.${lp("readyAt")}, 'servedAt', ${prep}.${lp("servedAt")})`;

  const progress = (order: string): string => {
    const event = (type: string): string =>
      ctx.record({
        type,
        payload: orderPayload("v_order", [
          ["number", "v_order.number"],
          ["customerId", "v_order.customer"],
        ]),
        subject: "'orders/' || v_order.id::text",
        tenant: "v_order.tenant",
        audit: false,
        key: `${sqlString(`${type}:`)} || v_order.id::text`,
      });

    return `select ${orderFields(ctx, "x")} into v_order from ${t("orders")} x where x.${o("id")} = ${order};
  select min(${rank(stateOf("p"))}) into v_least from ${t("preparations")} p where p.${lp("order")} = ${order};
  if v_least >= ${rank("'ready'")} then
    ${event("order.prepared")}
  end if;
  if v_least = ${rank("'served'")} then
    ${event("order.served")}
  end if;`;
  };

  const stamp = (state: string): string =>
    `${lp("startedAt")} = case when ${rank(state)} >= 2 then coalesce(p.${lp("startedAt")}, now()) end,
    ${lp("readyAt")} = case when ${rank(state)} >= 3 then coalesce(p.${lp("readyAt")}, now()) end,
    ${lp("servedAt")} = case when ${rank(state)} >= 4 then coalesce(p.${lp("servedAt")}, now()) end,
    ${lp("state")} = ${ctx.cast(PREPARATIONS, "state", state)},
    ${lp("updatedAt")} = now()${
      has("updatedBy")
        ? `,
    ${lp("updatedBy")} = auth.uid()`
        : ""
    }`;

  const receive = ctx.trigger("kitchen_receive");
  const changed = ctx.trigger("order_line_preparations_broadcast");
  const prefix = `${KITCHEN_TOPIC}:`;

  return `
-- Kitchen stations (grill, bar, cold) a line is prepared at, and the
-- products routed to each. Lines of an unrouted product go to the default.
create table if not exists ${t("kitchenStations")} (
  ${ks("id")} uuid primary key default gen_random_uuid(),
  ${ks("tenant")} ${ctx.idType} not null,
  ${ks("key")} text not null check (${ks("key")} ~ '^[a-z][a-z0-9_-]{0,62}$'),
  ${ks("name")} text not null check (length(${ks("name")}) between 1 and 200),
  ${ks("position")} integer not null default 0,
  ${ks("isDefault")} boolean not null default false,
  ${ks("active")} boolean not null default true,
  ${ks("createdAt")} timestamptz not null default now(),
  ${ks("updatedAt")} timestamptz not null default now(),
  unique (${ks("tenant")}, ${ks("key")})
);
create unique index if not exists ${sqlIdent(`${ctx.tableName("kitchenStations").name}_default_idx`)} on ${t("kitchenStations")} (${ks("tenant")}) where ${ks("isDefault")};
${lockModuleTable(ctx, "kitchenStations", { read: true })}
${policy("kitchenStations")}

create table if not exists ${t("kitchenRoutes")} (
  ${kr("product")} uuid primary key references ${products} on delete cascade,
  ${kr("tenant")} ${ctx.idType} not null,
  ${kr("station")} uuid not null references ${t("kitchenStations")} (${ks("id")}) on delete cascade
);${appUniqueIndex(ctx, "kitchenRoutes", ["product"])}
create index if not exists ${sqlIdent(`${ctx.tableName("kitchenRoutes").name}_${ctx.naming.rename("station_idx")}`)} on ${t("kitchenRoutes")} (${kr("station")});
${lockModuleTable(ctx, "kitchenRoutes", { read: true })}
${policy("kitchenRoutes")}

-- Where each line of an order sent to the kitchen is: queued, preparing,
-- ready or served, with when it reached each state.
create table if not exists ${t("preparations")} (
  ${lp("line")} uuid primary key references ${t("orderLines")} (${ol("id")}) on delete cascade,
  ${lp("tenant")} ${ctx.idType} not null,
  ${lp("order")} uuid not null references ${t("orders")} (${o("id")}) on delete cascade,
  ${lp("station")} uuid references ${t("kitchenStations")} (${ks("id")}) on delete set null,
  ${lp("state")} text not null default 'queued' check (${lp("state")} in (${PREPARATION_STATES.map(sqlString).join(", ")})),${
    has("note")
      ? `
  ${lp("note")} text check (length(${lp("note")}) <= 500),`
      : ""
  }
  ${lp("queuedAt")} timestamptz not null default now(),
  ${lp("startedAt")} timestamptz,
  ${lp("readyAt")} timestamptz,
  ${lp("servedAt")} timestamptz,
  ${lp("updatedAt")} timestamptz not null default now()${
    has("updatedBy")
      ? `,
  ${lp("updatedBy")} uuid`
      : ""
  }
);${appUniqueIndex(ctx, PREPARATIONS, ["line"])}
create index if not exists order_line_preparations_order_idx on ${t("preparations")} (${lp("order")});
create index if not exists order_line_preparations_station_idx on ${t("preparations")} (${lp("station")});
create index if not exists order_line_preparations_open_idx on ${t("preparations")} (${lp("tenant")}, ${lp("queuedAt")}) where ${lp("state")} <> 'served';
${lockModuleTable(ctx, PREPARATIONS, { read: true })}
${policy("preparations")}

-- Pings kitchen:{tenant} with the line, its order, station and state, so a
-- kitchen display and an order board refetch what moved.
create or replace function ${fn("order_line_preparations_changed")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and old.${lp("state")} = new.${lp("state")} and old.${lp("station")} is not distinct from new.${lp("station")} then
    return null;
  end if;
  ${ctx.broadcast(
    `${sqlString(prefix)} || new.${lp("tenant")}::text`,
    "'preparation'",
    `jsonb_build_object('lineId', new.${lp("line")}, 'orderId', new.${lp("order")}, 'stationId', new.${lp("station")}, 'state', ${stateOf("new")})`,
  )}
  return null;
end;
$$;
revoke execute on function ${fn("order_line_preparations_changed")}() from public, anon, authenticated;
drop trigger if exists ${changed} on ${t("preparations")};
create trigger ${changed} after insert or update on ${t("preparations")}
  for each row execute function ${fn("order_line_preparations_changed")}();
do $$
begin
  if to_regclass('realtime.messages') is not null then
        ${renderPolicy(
          makePolicy({
            table: "realtime.messages",
            name: receive,
            command: "select",
            roles: ["authenticated"],
            using: `realtime.messages.extension = 'broadcast'
        and (select realtime.topic()) like ${sqlString(`${prefix}%`)}
        and substr((select realtime.topic()), ${String(prefix.length + 1)}) in (
          select t::text from ${scope.ids(read)} t
          union all
          select t::text from ${scope.ids(prepare)} t
        )`,
          }),
          { drop: true, target: "realtime.messages" },
        )}
  end if;
end;
$$;

-- Creates or changes a station. attrs: key, name, position, default, active
-- and productIds, which replaces the products routed to it.
create or replace function ${fn("save_kitchen_station")}(tenant ${ctx.idType}, station uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  ${guard("save_kitchen_station.tenant", [manage])}
  if jsonb_typeof(attrs) is distinct from 'object' then
    ${fail("ORDERS_KITCHEN_STATION_INVALID", "attrs must be an object", "22023")}
  end if;
  if attrs ? 'productIds' and jsonb_typeof(attrs -> 'productIds') is distinct from 'array' then
    ${fail("ORDERS_KITCHEN_STATION_INVALID", "productIds must be a list", "22023")}
  end if;
  if coalesce((attrs ->> 'default')::boolean, false) then
    update ${t("kitchenStations")} s set ${ks("isDefault")} = false
    where s.${ks("tenant")} = save_kitchen_station.tenant and s.${ks("isDefault")} and s.${ks("id")} is distinct from save_kitchen_station.station;
  end if;
  if save_kitchen_station.station is null then
    insert into ${t("kitchenStations")} (${ks("tenant")}, ${ks("key")}, ${ks("name")}, ${ks("position")}, ${ks("isDefault")}, ${ks("active")})
    values (save_kitchen_station.tenant, attrs ->> 'key', coalesce(attrs ->> 'name', attrs ->> 'key'), coalesce((attrs ->> 'position')::integer, 0), coalesce((attrs ->> 'default')::boolean, false), coalesce((attrs ->> 'active')::boolean, true))
    returning ${ks("id")} into v_id;
  else
    update ${t("kitchenStations")} s set
      ${ks("key")} = coalesce(attrs ->> 'key', s.${ks("key")}),
      ${ks("name")} = coalesce(attrs ->> 'name', s.${ks("name")}),
      ${ks("position")} = coalesce((attrs ->> 'position')::integer, s.${ks("position")}),
      ${ks("isDefault")} = coalesce((attrs ->> 'default')::boolean, s.${ks("isDefault")}),
      ${ks("active")} = coalesce((attrs ->> 'active')::boolean, s.${ks("active")}),
      ${ks("updatedAt")} = now()
    where s.${ks("id")} = save_kitchen_station.station and s.${ks("tenant")} = save_kitchen_station.tenant
    returning s.${ks("id")} into v_id;
    if v_id is null then
      ${fail("ORDERS_KITCHEN_STATION_NOT_FOUND", "no such kitchen station", "P0002")}
    end if;
  end if;
  if attrs ? 'productIds' then
    if exists (
      select 1 from jsonb_array_elements_text(attrs -> 'productIds') e(value)
      where not exists (
        select 1 from ${catalog.table("products")} p
        where p.${catalog.col("products", "id")}::text = e.value and p.${catalog.col("products", "tenant")}::text = save_kitchen_station.tenant::text
      )
    ) then
      ${fail("ORDERS_KITCHEN_STATION_INVALID", "productIds must name products of this organization", "22023")}
    end if;
    delete from ${t("kitchenRoutes")} r where r.${kr("station")} = v_id;
    insert into ${t("kitchenRoutes")} (${kr("product")}, ${kr("tenant")}, ${kr("station")})
    select distinct e.value::uuid, save_kitchen_station.tenant, v_id
    from jsonb_array_elements_text(attrs -> 'productIds') e(value)
    on conflict (${kr("product")}) do update set ${kr("station")} = excluded.${kr("station")};
  end if;
  return (select ${stationJson("s")} from ${t("kitchenStations")} s where s.${ks("id")} = v_id);
end;
$$;
${userGrant(`${fn("save_kitchen_station")}(${ctx.idType}, uuid, jsonb)`)}

create or replace function ${fn("delete_kitchen_station")}(station uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  select s.${ks("tenant")} into v_tenant from ${t("kitchenStations")} s where s.${ks("id")} = delete_kitchen_station.station;
  if v_tenant is null then
    return false;
  end if;
  ${guard("v_tenant", [manage])}
  delete from ${t("kitchenStations")} s where s.${ks("id")} = delete_kitchen_station.station;
  return true;
end;
$$;
${userGrant(`${fn("delete_kitchen_station")}(uuid)`)}

-- A tenant's stations in display order, with their routed products.
create or replace function ${fn("kitchen_stations")}(tenant ${ctx.idType})
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${stationJson("s")} order by s.${ks("position")}, s.${ks("name")}), '[]'::jsonb)
  from ${t("kitchenStations")} s
  where s.${ks("tenant")} = kitchen_stations.tenant
$$;
${userGrant(`${fn("kitchen_stations")}(${ctx.idType})`)}

-- Sends an order's lines to the kitchen: each line not sent yet is queued at
-- its product's active station, or the default one. notes maps a line id to
-- a note for the cook. Sending again queues only lines added since.
create or replace function ${fn("send_order_to_kitchen")}(order_id uuid, notes jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order record;
  v_count integer;
begin
  select ${orderFields(ctx, "x")} into v_order from ${t("orders")} x where x.${o("id")} = send_order_to_kitchen.order_id;
  if v_order.id is null then
    ${fail("ORDERS_ORDER_NOT_FOUND", "order not found", "P0002")}
  end if;
  ${guard("v_order.tenant", [prepare, manage])}
  if v_order.status in ('cancelled', 'refunded') then
    ${fail("ORDERS_KITCHEN_CLOSED", "a cancelled or refunded order can't go to the kitchen", "22023")}
  end if;
  if notes is not null and jsonb_typeof(notes) <> 'object' then
    ${fail("ORDERS_KITCHEN_NOTES_INVALID", "notes must map line ids to text", "22023")}
  end if;
  insert into ${t("preparations")} (${lp("line")}, ${lp("tenant")}, ${lp("order")}, ${lp("station")}${has("note") ? `, ${lp("note")}` : ""}${has("updatedBy") ? `, ${lp("updatedBy")}` : ""})
  select l.${ol("id")}, v_order.tenant, v_order.id,
    coalesce(
      (select s.${ks("id")} from ${t("kitchenRoutes")} r join ${t("kitchenStations")} s on s.${ks("id")} = r.${kr("station")} where r.${kr("product")} = l.${ol("product")} and s.${ks("active")}),
      (select s.${ks("id")} from ${t("kitchenStations")} s where s.${ks("tenant")} = v_order.tenant and s.${ks("isDefault")} and s.${ks("active")})
    )${
      has("note")
        ? `,
    left(nullif(trim(send_order_to_kitchen.notes ->> l.${ol("id")}::text), ''), 500)`
        : ""
    }${has("updatedBy") ? ",\n    auth.uid()" : ""}
  from ${t("orderLines")} l
  where l.${ol("order")} = v_order.id
  on conflict (${lp("line")}) do nothing;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
${userGrant(`${fn("send_order_to_kitchen")}(uuid, jsonb)`)}

-- Moves one line to state. Moving back (a recalled dish) clears the later
-- times. Every line ready emits order.prepared, every line served
-- order.served, once per order.
create or replace function ${fn("set_line_preparation")}(line uuid, state text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_order_id uuid;
  v_order record;
  v_least integer;
begin
  select p.${lp("tenant")}, p.${lp("order")} into v_tenant, v_order_id
  from ${t("preparations")} p where p.${lp("line")} = set_line_preparation.line;
  if v_tenant is null then
    ${fail("ORDERS_PREPARATION_NOT_FOUND", "the line was not sent to the kitchen", "P0002")}
  end if;
  ${guard("v_tenant", [prepare, manage])}
  if ${rank("set_line_preparation.state")} is null then
    ${fail("ORDERS_PREPARATION_STATE_INVALID", "state must be queued, preparing, ready or served", "22023")}
  end if;
  update ${t("preparations")} p set
    ${stamp("set_line_preparation.state")}
  where p.${lp("line")} = set_line_preparation.line;
  ${progress("v_order_id")}
  return (
    select ${lineJson("p", "l")}
    from ${t("preparations")} p join ${t("orderLines")} l on l.${ol("id")} = p.${lp("line")}
    where p.${lp("line")} = set_line_preparation.line
  );
end;
$$;
${userGrant(`${fn("set_line_preparation")}(uuid, text)`)}

-- Moves every line of an order (at one station, or all) that is behind
-- state up to it: a cook bumps a ticket, a runner marks it served.
create or replace function ${fn("bump_kitchen_ticket")}(order_id uuid, station uuid, state text)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order record;
  v_least integer;
  v_count integer;
begin
  select ${orderFields(ctx, "x")} into v_order from ${t("orders")} x where x.${o("id")} = bump_kitchen_ticket.order_id;
  if v_order.id is null then
    ${fail("ORDERS_ORDER_NOT_FOUND", "order not found", "P0002")}
  end if;
  ${guard("v_order.tenant", [prepare, manage])}
  if ${rank("bump_kitchen_ticket.state")} is null then
    ${fail("ORDERS_PREPARATION_STATE_INVALID", "state must be queued, preparing, ready or served", "22023")}
  end if;
  update ${t("preparations")} p set
    ${stamp("bump_kitchen_ticket.state")}
  where p.${lp("order")} = v_order.id
    and (bump_kitchen_ticket.station is null or p.${lp("station")} = bump_kitchen_ticket.station)
    and ${rank(stateOf("p"))} < ${rank("bump_kitchen_ticket.state")};
  get diagnostics v_count = row_count;
  if v_count > 0 then
    ${progress("v_order.id")}
  end if;
  return v_count;
end;
$$;
${userGrant(`${fn("bump_kitchen_ticket")}(uuid, uuid, text)`)}

-- A kitchen display's tickets: per order, its lines at station (every
-- station when null) in states, oldest ticket first.
create or replace function ${fn("kitchen_queue")}(tenant ${ctx.idType}, station uuid, states text[], page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(ticket order by ticket ->> 'sentAt', ticket ->> 'orderId'), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'orderId', o.${o("id")},
      'number', o.${o("number")},
      'sentAt', min(p.${lp("queuedAt")}),
      'lines', jsonb_agg(${lineJson("p", "l")} order by l.${ol("position")}, l.${ol("id")})
    ) as ticket
    from ${t("preparations")} p
    join ${t("orderLines")} l on l.${ol("id")} = p.${lp("line")}
    join ${t("orders")} o on o.${o("id")} = p.${lp("order")}
    where p.${lp("tenant")} = kitchen_queue.tenant
      and (kitchen_queue.station is null or p.${lp("station")} = kitchen_queue.station)
      and ${stateOf("p")} = any (coalesce(kitchen_queue.states, array['queued', 'preparing', 'ready']))
    group by o.${o("id")}, o.${o("number")}
    order by min(p.${lp("queuedAt")}), o.${o("id")}
    limit ${pageSize("kitchen_queue.page_size", 100, 500)}
  ) tickets
$$;
${userGrant(`${fn("kitchen_queue")}(${ctx.idType}, uuid, text[], integer)`)}

-- An order-state board: each order sent to the kitchen since since, in the
-- state of its least advanced line, with how many lines are in each state.
create or replace function ${fn("order_board")}(tenant ${ctx.idType}, since timestamptz, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(card order by card ->> 'sentAt', card ->> 'orderId'), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'orderId', o.${o("id")},
      'number', o.${o("number")},
      'customerId', o.${o("customer")},
      'status', ${ctx.label("orders", "status", `o.${o("status")}`)},
      'state', (${STATES})[min(${rank(stateOf("p"))})],
      'sentAt', min(p.${lp("queuedAt")}),
      'readyAt', case when bool_and(p.${lp("readyAt")} is not null) then max(p.${lp("readyAt")}) end,
      'servedAt', case when bool_and(p.${lp("servedAt")} is not null) then max(p.${lp("servedAt")}) end,
      'counts', jsonb_build_object(
        'queued', count(*) filter (where p.${lp("state")} = 'queued'),
        'preparing', count(*) filter (where p.${lp("state")} = 'preparing'),
        'ready', count(*) filter (where p.${lp("state")} = 'ready'),
        'served', count(*) filter (where p.${lp("state")} = 'served')
      )
    ) as card
    from ${t("preparations")} p
    join ${t("orders")} o on o.${o("id")} = p.${lp("order")}
    where p.${lp("tenant")} = order_board.tenant
    group by o.${o("id")}, o.${o("number")}, o.${o("customer")}, o.${o("status")}
    having min(p.${lp("queuedAt")}) >= coalesce(order_board.since, now() - interval '1 day')
    order by min(p.${lp("queuedAt")}), o.${o("id")}
    limit ${pageSize("order_board.page_size", 200, 1000)}
  ) cards
$$;
${userGrant(`${fn("order_board")}(${ctx.idType}, timestamptz, integer)`)}
`;
}

/** The functions `options.kitchen` adds to the orders contract. */
export function kitchenContract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "save_kitchen_station",
      args: ["{id}", "uuid", "jsonb"],
      returns: "jsonb",
    },
    { name: "delete_kitchen_station", args: ["uuid"], returns: "boolean" },
    { name: "kitchen_stations", args: ["{id}"], returns: "jsonb" },
    {
      name: "send_order_to_kitchen",
      args: ["uuid", "jsonb"],
      returns: "integer",
    },
    { name: "set_line_preparation", args: ["uuid", "text"], returns: "jsonb" },
    {
      name: "bump_kitchen_ticket",
      args: ["uuid", "uuid", "text"],
      returns: "integer",
    },
    {
      name: "kitchen_queue",
      args: ["{id}", "uuid", "text[]", "integer"],
      returns: "jsonb",
    },
    {
      name: "order_board",
      args: ["{id}", "timestamptz", "integer"],
      returns: "jsonb",
    },
  ];
}
