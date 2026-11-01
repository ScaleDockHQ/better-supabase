import type { InvoicesEvents } from "../../blocks/invoices/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlTableSpec,
} from "../context.ts";
import type { CollectionHelpers } from "./invoices-collections.ts";
import type { InvoiceNames } from "./invoices-names.ts";
import type { BlockSqlOperations } from "./permissions-model.ts";

import { hasLegalEntityColumn } from "../numbering-sql.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { fail, userGrant } from "../shared.ts";
import { lockModuleTable } from "./over-app.ts";

const INVOICE = [
  "organizationId",
  "invoiceId",
  "subjectType",
  "subjectId",
  "identifier",
] as const;

const DELIVERY = [
  ...INVOICE,
  "channel",
  "messageId",
  "status",
  "reason",
] as const;

/** The events a sent or received e-invoice records on its invoice. */
export const E_DELIVERY_EVENTS: BlockSqlEvents<InvoicesEvents> = {
  "invoice.e_invoice_sent": { subject: "invoices", payload: [...DELIVERY] },
  "invoice.e_invoice_delivered": {
    subject: "invoices",
    payload: [...DELIVERY],
  },
  "invoice.e_invoice_rejected": { subject: "invoices", payload: [...DELIVERY] },
  "invoice.e_invoice_received": { subject: "invoices", payload: [...DELIVERY] },
};

/** What e-invoice delivery adds to the invoice names. */
export interface EDeliveryNames {
  /** `invoices.send`: sends invoices over a network and records deliveries. */
  readonly send: string;
}

export function eDeliveryNames(
  ctx: BlockSqlContext,
  keys: BlockSqlOperations<"invoices">,
): EDeliveryNames {
  return { send: ctx.permission("send", keys.send) };
}

/**
 * The `invoice_e_endpoints` table: the Peppol participant id (an EAS scheme and
 * an id) of an organization, a legal entity or a company.
 */
export const E_ENDPOINTS_TABLE: BlockSqlTableSpec = {
  name: "invoice_e_endpoints",
  app: {},
  optionalTable: true,
  lifecycle: { tenant: "tenant", export: true },
  columns: {
    id: "id",
    tenant: "tenant_id",
    partyKind: "party_kind",
    partyId: "party_id",
    scheme: "scheme",
    endpoint: "endpoint_id",
    createdAt: "created_at",
    updatedAt: "updated_at",
  },
};

/**
 * The `invoice_e_deliveries` table: one row per e-invoice a channel took from
 * the app or delivered to it, unique per channel and message id.
 */
export const E_DELIVERIES_TABLE: BlockSqlTableSpec = {
  name: "invoice_e_deliveries",
  app: {},
  optionalTable: true,
  lifecycle: { tenant: "tenant", export: true },
  columns: {
    id: "id",
    tenant: "tenant_id",
    invoice: "invoice_id",
    direction: "direction",
    format: "format",
    channel: "channel",
    messageId: "message_id",
    state: "state",
    reason: "reason",
    documentHash: "document_hash",
    createdAt: "created_at",
    updatedAt: "updated_at",
  },
};

/** Whether e-invoice delivery is on: both tables are there. */
function hasEDelivery(ctx: BlockSqlContext): boolean {
  return ctx.hasTable("eEndpoints") && ctx.hasTable("eDeliveries");
}

/** The endpoint and delivery tables with their indexes and read policies. */
export function eDeliveryTablesSql(
  ctx: BlockSqlContext,
  invoices: string,
  invoiceId: string,
  read: string,
): string {
  if (!hasEDelivery(ctx)) {
    return "";
  }

  const endpoints = ctx.table("eEndpoints");
  const deliveries = ctx.table("eDeliveries");
  const p = (column: string): string => ctx.col("eEndpoints", column);
  const d = (column: string): string => ctx.col("eDeliveries", column);

  const readPolicy = (name: string, tenant: string, target: string): string =>
    renderPolicy(
      makePolicy({
        table: target,
        name: ctx.naming.rename(name),
        command: "select",
        roles: ["authenticated"],
        using: ctx.scope.check(tenant, read),
      }),
      { drop: true, target },
    );

  return `
create table if not exists ${endpoints} (
  ${p("id")} uuid primary key default gen_random_uuid(),
  ${p("tenant")} ${ctx.idType} not null,
  ${p("partyKind")} text not null check (${p("partyKind")} in ('organization', 'legal_entity', 'company')),
  ${p("partyId")} text not null check (length(${p("partyId")}) between 1 and 150),
  -- The Electronic Address Scheme code from the Peppol EAS list, such as 0106.
  ${p("scheme")} text not null check (${p("scheme")} ~ '^[0-9]{4}$'),
  ${p("endpoint")} text not null check (length(${p("endpoint")}) between 1 and 200),
  ${p("createdAt")} timestamptz not null default now(),
  ${p("updatedAt")} timestamptz not null default now()
);
create unique index if not exists ${ctx.naming.rename("invoice_e_endpoints_party_key")} on ${endpoints} (${p("tenant")}, ${p("partyKind")}, ${p("partyId")});
create index if not exists ${ctx.naming.rename("invoice_e_endpoints_lookup_idx")} on ${endpoints} (${p("tenant")}, ${p("scheme")}, ${p("endpoint")});
${lockModuleTable(ctx, "eEndpoints", { read: true })}
${readPolicy("invoice_e_endpoints_read", p("tenant"), endpoints)}

create table if not exists ${deliveries} (
  ${d("id")} uuid primary key default gen_random_uuid(),
  ${d("tenant")} ${ctx.idType} not null,
  ${d("invoice")} uuid references ${invoices} (${invoiceId}) on delete set null,
  ${d("direction")} text not null check (${d("direction")} in ('outbound', 'inbound')),
  ${d("format")} text check (${d("format")} is null or length(${d("format")}) between 1 and 100),
  ${d("channel")} text not null check (length(${d("channel")}) between 1 and 100),
  ${d("messageId")} text not null check (length(${d("messageId")}) between 1 and 300),
  ${d("state")} text not null check (${d("state")} in ('pending', 'delivered', 'rejected', 'received', 'unmatched')),
  ${d("reason")} text check (${d("reason")} is null or length(${d("reason")}) <= 2000),
  ${d("documentHash")} text check (${d("documentHash")} is null or ${d("documentHash")} ~ '^[0-9a-f]{64}$'),
  ${d("createdAt")} timestamptz not null default now(),
  ${d("updatedAt")} timestamptz not null default now()
);
create unique index if not exists ${ctx.naming.rename("invoice_e_deliveries_message_key")} on ${deliveries} (${d("tenant")}, ${d("channel")}, ${d("messageId")});
create index if not exists ${ctx.naming.rename("invoice_e_deliveries_invoice_idx")} on ${deliveries} (${d("invoice")}, ${d("tenant")});
create index if not exists ${ctx.naming.rename("invoice_e_deliveries_state_idx")} on ${deliveries} (${d("tenant")}, ${d("direction")}, ${d("state")});
${lockModuleTable(ctx, "eDeliveries", { read: true })}
${readPolicy("invoice_e_deliveries_read", d("tenant"), deliveries)}
`;
}

/**
 * Peppol participant ids and the delivery log: `set_invoice_e_endpoint`,
 * `invoice_e_endpoints`, `find_e_endpoint_party`, `record_e_invoice_delivery`,
 * `set_e_invoice_delivery_state` and `list_e_invoice_deliveries`.
 */
export function eDeliverySql(
  ctx: BlockSqlContext,
  n: InvoiceNames,
  h: CollectionHelpers,
): string {
  if (!hasEDelivery(ctx)) {
    return "";
  }

  const { fn, t } = n;
  const { i } = h;
  const endpoints = ctx.table("eEndpoints");
  const deliveries = ctx.table("eDeliveries");
  const p = (column: string): string => ctx.col("eEndpoints", column);
  const d = (column: string): string => ctx.col("eDeliveries", column);

  const allowed = (tenant: string, permission: string): string =>
    `(${n.service} or ${ctx.scope.can(tenant, permission)})`;

  const entity = hasLegalEntityColumn(ctx, "invoices")
    ? `v_row.legal_entity_id::text`
    : "null::text";

  const buyer = ctx.has("invoices", "companyId")
    ? `v_row.${i("companyId")}::text`
    : "null::text";

  const endpointJson = (alias: string): string =>
    `jsonb_build_object('scheme', ${alias}.${p("scheme")}, 'id', ${alias}.${p("endpoint")})`;

  const deliveryJson = (alias: string): string =>
    `jsonb_build_object('id', ${alias}.${d("id")}, 'organizationId', ${alias}.${d("tenant")}, 'invoiceId', ${alias}.${d("invoice")}, 'direction', ${alias}.${d("direction")}, 'format', ${alias}.${d("format")}, 'channel', ${alias}.${d("channel")}, 'messageId', ${alias}.${d("messageId")}, 'state', ${alias}.${d("state")}, 'reason', ${alias}.${d("reason")}, 'documentHash', ${alias}.${d("documentHash")}, 'createdAt', ${alias}.${d("createdAt")}, 'updatedAt', ${alias}.${d("updatedAt")})`;

  const eventExtra = (alias: string): string =>
    `, 'channel', ${alias}.${d("channel")}, 'messageId', ${alias}.${d("messageId")}, 'status', ${alias}.${d("state")}, 'reason', ${alias}.${d("reason")}`;

  return `
-- Sets the Peppol participant id of an organization ('organization' with the
-- organization id), a legal entity or a company. A null scheme and endpoint
-- remove it. Needs invoices.manage.
create or replace function ${fn("set_invoice_e_endpoint")}(tenant ${ctx.idType}, party_kind text, party_id text, scheme text default null, endpoint_id text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${endpoints};
begin
  if not ${allowed("set_invoice_e_endpoint.tenant", n.manage)} then
    ${fail("INVOICE_FORBIDDEN", "not allowed to manage invoices in this organization", "42501")}
  end if;
  if set_invoice_e_endpoint.party_kind not in ('organization', 'legal_entity', 'company')
    or nullif(trim(set_invoice_e_endpoint.party_id), '') is null
    or length(set_invoice_e_endpoint.party_id) > 150 then
    ${fail("EINVOICE_ENDPOINT_INVALID", "party_kind is organization, legal_entity or company, and party_id is a non-empty text of at most 150 characters", "22023")}
  end if;
  if set_invoice_e_endpoint.scheme is null and set_invoice_e_endpoint.endpoint_id is null then
    delete from ${endpoints} x
    where x.${p("tenant")} = set_invoice_e_endpoint.tenant
      and x.${p("partyKind")} = set_invoice_e_endpoint.party_kind
      and x.${p("partyId")} = set_invoice_e_endpoint.party_id;
    return null;
  end if;
  if set_invoice_e_endpoint.scheme !~ '^[0-9]{4}$'
    or nullif(trim(set_invoice_e_endpoint.endpoint_id), '') is null
    or length(set_invoice_e_endpoint.endpoint_id) > 200 then
    ${fail("EINVOICE_ENDPOINT_INVALID", "an endpoint is a four-digit EAS scheme and a non-empty id of at most 200 characters", "22023")}
  end if;
  insert into ${endpoints} (${p("tenant")}, ${p("partyKind")}, ${p("partyId")}, ${p("scheme")}, ${p("endpoint")})
  values (set_invoice_e_endpoint.tenant, set_invoice_e_endpoint.party_kind, set_invoice_e_endpoint.party_id, set_invoice_e_endpoint.scheme, trim(set_invoice_e_endpoint.endpoint_id))
  on conflict (${p("tenant")}, ${p("partyKind")}, ${p("partyId")}) do update
    set ${p("scheme")} = excluded.${p("scheme")}, ${p("endpoint")} = excluded.${p("endpoint")}, ${p("updatedAt")} = now()
  returning * into v_row;
  return ${endpointJson("v_row")};
end;
$$;
${userGrant(`${fn("set_invoice_e_endpoint")}(${ctx.idType}, text, text, text, text)`)}

-- The Peppol participant ids of an invoice: the seller (its legal entity, else
-- the organization) and the buyer (its company). Each is null when none is set.
create or replace function ${fn("invoice_e_endpoints")}(invoice uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row ${t("invoices")};
  v_seller jsonb;
  v_buyer jsonb;
begin
  select * into v_row from ${t("invoices")} x where x.${i("id")} = invoice_e_endpoints.invoice and ${h.can("x", n.read)};
  if v_row.${i("id")} is null then
    ${fail("INVOICE_NOT_FOUND", "no such invoice you can read", "P0002")}
  end if;
  select coalesce(
    (select ${endpointJson("e")} from ${endpoints} e where e.${p("tenant")} = v_row.${i("tenant")} and e.${p("partyKind")} = 'legal_entity' and e.${p("partyId")} = ${entity}),
    (select ${endpointJson("e")} from ${endpoints} e where e.${p("tenant")} = v_row.${i("tenant")} and e.${p("partyKind")} = 'organization' and e.${p("partyId")} = v_row.${i("tenant")}::text)
  ) into v_seller;
  select ${endpointJson("e")} into v_buyer from ${endpoints} e
  where e.${p("tenant")} = v_row.${i("tenant")} and e.${p("partyKind")} = 'company' and e.${p("partyId")} = ${buyer};
  return jsonb_build_object('seller', v_seller, 'buyer', v_buyer);
end;
$$;
${userGrant(`${fn("invoice_e_endpoints")}(uuid)`)}

-- The party that has a participant id: { partyKind, partyId }, or null. A
-- received document's supplier is found by it.
create or replace function ${fn("find_e_endpoint_party")}(tenant ${ctx.idType}, scheme text, endpoint_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ${allowed("find_e_endpoint_party.tenant", n.read)} then
    ${fail("INVOICE_FORBIDDEN", "not allowed to read this organization's invoices", "42501")}
  end if;
  return (
    select jsonb_build_object('partyKind', e.${p("partyKind")}, 'partyId', e.${p("partyId")})
    from ${endpoints} e
    where e.${p("tenant")} = find_e_endpoint_party.tenant
      and e.${p("scheme")} = find_e_endpoint_party.scheme
      and lower(e.${p("endpoint")}) = lower(find_e_endpoint_party.endpoint_id)
    order by case e.${p("partyKind")} when 'company' then 0 else 1 end, e.${p("createdAt")}
    limit 1
  );
end;
$$;
${userGrant(`${fn("find_e_endpoint_party")}(${ctx.idType}, text, text)`)}

-- Records a document a channel took from the app (outbound, pending) or
-- delivered to it (inbound, received with an invoice, else unmatched). A repeat
-- of the same channel and message id changes nothing and returns created =
-- false. Needs invoices.send. Returns { created, delivery }.
create or replace function ${fn("record_e_invoice_delivery")}(tenant ${ctx.idType}, direction text, channel text, message_id text, format text default null, state text default null, invoice uuid default null, reason text default null, document_hash text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${t("invoices")};
  v_delivery ${deliveries};
  v_state text;
  v_created boolean := true;
begin
  if not ${allowed("record_e_invoice_delivery.tenant", n.send)} then
    ${fail("INVOICE_FORBIDDEN", "not allowed to send invoices in this organization", "42501")}
  end if;
  if record_e_invoice_delivery.direction not in ('outbound', 'inbound') then
    ${fail("EINVOICE_DELIVERY_INVALID", "direction is outbound or inbound", "22023")}
  end if;
  v_state := coalesce(record_e_invoice_delivery.state, case
    when record_e_invoice_delivery.direction = 'outbound' then 'pending'
    when record_e_invoice_delivery.invoice is null then 'unmatched'
    else 'received' end);
  if v_state not in ('pending', 'delivered', 'rejected', 'received', 'unmatched')
    or (record_e_invoice_delivery.direction = 'outbound' and v_state in ('received', 'unmatched'))
    or (record_e_invoice_delivery.direction = 'inbound' and v_state in ('pending', 'delivered', 'rejected'))
    or (v_state in ('pending', 'delivered', 'rejected') and record_e_invoice_delivery.invoice is null)
    or nullif(trim(record_e_invoice_delivery.channel), '') is null
    or nullif(trim(record_e_invoice_delivery.message_id), '') is null then
    ${fail("EINVOICE_DELIVERY_INVALID", "a delivery needs a channel and a message id, and a state that fits its direction (an outbound one an invoice)", "22023")}
  end if;
  if record_e_invoice_delivery.invoice is not null then
    select * into v_row from ${t("invoices")} x
    where x.${i("id")} = record_e_invoice_delivery.invoice and x.${i("tenant")} = record_e_invoice_delivery.tenant;
    if v_row.${i("id")} is null then
      ${fail("INVOICE_NOT_FOUND", "no such invoice in this organization", "P0002")}
    end if;
  end if;
  insert into ${deliveries} (${d("tenant")}, ${d("invoice")}, ${d("direction")}, ${d("format")}, ${d("channel")}, ${d("messageId")}, ${d("state")}, ${d("reason")}, ${d("documentHash")})
  values (record_e_invoice_delivery.tenant, record_e_invoice_delivery.invoice, record_e_invoice_delivery.direction, nullif(trim(record_e_invoice_delivery.format), ''), record_e_invoice_delivery.channel, record_e_invoice_delivery.message_id, v_state, nullif(trim(record_e_invoice_delivery.reason), ''), record_e_invoice_delivery.document_hash)
  on conflict (${d("tenant")}, ${d("channel")}, ${d("messageId")}) do nothing
  returning * into v_delivery;
  if v_delivery.${d("id")} is null then
    v_created := false;
    select * into v_delivery from ${deliveries} x
    where x.${d("tenant")} = record_e_invoice_delivery.tenant and x.${d("channel")} = record_e_invoice_delivery.channel and x.${d("messageId")} = record_e_invoice_delivery.message_id;
  elsif v_row.${i("id")} is not null then
    if v_state = 'received' then
      ${h.record("invoice.e_invoice_received", "v_row", eventExtra("v_delivery"), true)}
    else
      ${h.record("invoice.e_invoice_sent", "v_row", eventExtra("v_delivery"), true)}
    end if;
  end if;
  return jsonb_build_object('created', v_created, 'delivery', ${deliveryJson("v_delivery")});
end;
$$;
${userGrant(`${fn("record_e_invoice_delivery")}(${ctx.idType}, text, text, text, text, text, uuid, text, text)`)}

-- Moves a delivery on: a pending one to delivered or rejected, an unmatched
-- one to received (with the invoice it became) or unmatched again with a new
-- reason. Needs invoices.send. Returns the delivery.
create or replace function ${fn("set_e_invoice_delivery_state")}(delivery uuid, state text, reason text default null, invoice uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_delivery ${deliveries};
  v_row ${t("invoices")};
  v_target uuid;
begin
  select * into v_delivery from ${deliveries} x
  where x.${d("id")} = set_e_invoice_delivery_state.delivery and ${allowed(`x.${d("tenant")}`, n.send)} for update;
  if v_delivery.${d("id")} is null then
    ${fail("EINVOICE_DELIVERY_NOT_FOUND", "no such delivery you can update", "P0002")}
  end if;
  if not (
    (v_delivery.${d("state")} = 'pending' and set_e_invoice_delivery_state.state in ('delivered', 'rejected'))
    or (v_delivery.${d("state")} = 'unmatched' and set_e_invoice_delivery_state.state in ('received', 'unmatched'))
  ) then
    ${fail("EINVOICE_DELIVERY_STATE", "a pending delivery becomes delivered or rejected, an unmatched one received or unmatched", "55000")}
  end if;
  v_target := coalesce(set_e_invoice_delivery_state.invoice, v_delivery.${d("invoice")});
  if set_e_invoice_delivery_state.state = 'received' and v_target is null then
    ${fail("EINVOICE_DELIVERY_INVALID", "a received delivery names the invoice it became", "22023")}
  end if;
  if v_target is not null then
    select * into v_row from ${t("invoices")} x
    where x.${i("id")} = v_target and x.${i("tenant")} = v_delivery.${d("tenant")};
    if v_row.${i("id")} is null then
      ${fail("INVOICE_NOT_FOUND", "no such invoice in this organization", "P0002")}
    end if;
  end if;
  update ${deliveries} x set
    ${d("state")} = set_e_invoice_delivery_state.state,
    ${d("reason")} = nullif(trim(set_e_invoice_delivery_state.reason), ''),
    ${d("invoice")} = v_target,
    ${d("updatedAt")} = now()
  where x.${d("id")} = v_delivery.${d("id")}
  returning * into v_delivery;
  if v_row.${i("id")} is not null and v_delivery.${d("state")} <> 'unmatched' then
    if v_delivery.${d("state")} = 'delivered' then
      ${h.record("invoice.e_invoice_delivered", "v_row", eventExtra("v_delivery"), true)}
    elsif v_delivery.${d("state")} = 'rejected' then
      ${h.record("invoice.e_invoice_rejected", "v_row", eventExtra("v_delivery"), true)}
    else
      ${h.record("invoice.e_invoice_received", "v_row", eventExtra("v_delivery"), true)}
    end if;
  end if;
  return ${deliveryJson("v_delivery")};
end;
$$;
${userGrant(`${fn("set_e_invoice_delivery_state")}(uuid, text, text, uuid)`)}

-- The deliveries of an organization, newest first, at most 500, filtered by
-- direction, state or invoice.
create or replace function ${fn("list_e_invoice_deliveries")}(tenant ${ctx.idType}, direction text default null, state text default null, invoice uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ${allowed("list_e_invoice_deliveries.tenant", n.read)} then
    ${fail("INVOICE_FORBIDDEN", "not allowed to read this organization's invoices", "42501")}
  end if;
  return coalesce((
    select jsonb_agg(${deliveryJson("x")} order by x.${d("createdAt")} desc)
    from (
      select * from ${deliveries} y
      where y.${d("tenant")} = list_e_invoice_deliveries.tenant
        and (list_e_invoice_deliveries.direction is null or y.${d("direction")} = list_e_invoice_deliveries.direction)
        and (list_e_invoice_deliveries.state is null or y.${d("state")} = list_e_invoice_deliveries.state)
        and (list_e_invoice_deliveries.invoice is null or y.${d("invoice")} = list_e_invoice_deliveries.invoice)
      order by y.${d("createdAt")} desc
      limit 500
    ) x
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_e_invoice_deliveries")}(${ctx.idType}, text, text, uuid)`)}
`;
}

/** The contract of the e-invoice functions. */
export function eDeliveryContract(
  ctx: BlockSqlContext,
): readonly BlockSqlContractFunction[] {
  if (!hasEDelivery(ctx)) {
    return [];
  }

  return [
    {
      name: "set_invoice_e_endpoint",
      args: ["{id}", "text", "text", "text", "text"],
      returns: "jsonb",
    },
    { name: "invoice_e_endpoints", args: ["uuid"], returns: "jsonb" },
    {
      name: "find_e_endpoint_party",
      args: ["{id}", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "record_e_invoice_delivery",
      args: [
        "{id}",
        "text",
        "text",
        "text",
        "text",
        "text",
        "uuid",
        "text",
        "text",
      ],
      returns: "jsonb",
    },
    {
      name: "set_e_invoice_delivery_state",
      args: ["uuid", "text", "text", "uuid"],
      returns: "jsonb",
    },
    {
      name: "list_e_invoice_deliveries",
      args: ["{id}", "text", "text", "uuid"],
      returns: "jsonb",
    },
  ];
}
