import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlTableSpec,
} from "../context.ts";
import type { InvoiceNames } from "./invoices-names.ts";

import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { fail, userGrant } from "../shared.ts";
import { lockModuleTable } from "./over-app.ts";

/**
 * The `invoice_deliveries` table: the e-invoices an invoice was sent as, with
 * the channel's reference (ADR 0175).
 */
export const DELIVERIES_TABLE: BlockSqlTableSpec = {
  name: "invoice_deliveries",
  app: {},
  optionalTable: true,
  lifecycle: { tenant: "tenant", export: true },
  columns: {
    id: "id",
    tenant: "tenant_id",
    invoice: "invoice_id",
    channel: "channel",
    format: "format",
    externalRef: "external_ref",
    filename: "filename",
    sentBy: "sent_by",
    sentAt: "sent_at",
  },
  optional: ["filename", "sentBy"],
};

const hasDeliveries = (ctx: BlockSqlContext): boolean =>
  ctx.hasTable("deliveries");

/** The deliveries table, its index and its read policy. */
export function deliveriesTableSql(
  ctx: BlockSqlContext,
  invoices: string,
  invoiceId: string,
  read: string,
): string {
  if (!hasDeliveries(ctx)) {
    return "";
  }

  const table = ctx.table("deliveries");
  const d = (column: string): string => ctx.col("deliveries", column);

  const optional = (logical: string, definition: () => string): string =>
    ctx.has("deliveries", logical) ? `\n  ${d(logical)} ${definition()},` : "";

  return `
-- The e-invoices an invoice was sent as: the channel, the format and the
-- reference the channel gave back. The same reference is kept once per invoice
-- and channel, so a retried record changes nothing.
create table if not exists ${table} (
  ${d("id")} uuid primary key default gen_random_uuid(),
  ${d("tenant")} ${ctx.idType} not null,
  ${d("invoice")} uuid not null references ${invoices} (${invoiceId}) on delete cascade,
  ${d("channel")} text not null check (length(${d("channel")}) between 1 and 100),
  ${d("format")} text not null check (length(${d("format")}) between 1 and 100),
  ${d("externalRef")} text not null check (length(${d("externalRef")}) between 1 and 500),${optional("filename", () => `text check (length(${d("filename")}) <= 255)`)}${optional("sentBy", () => "uuid")}
  ${d("sentAt")} timestamptz not null default now()
);
create unique index if not exists ${ctx.naming.rename("invoice_deliveries_ref_key")} on ${table} (${d("invoice")}, ${d("channel")}, ${d("externalRef")});
create index if not exists ${ctx.naming.rename("invoice_deliveries_tenant_idx")} on ${table} (${d("tenant")}, ${d("sentAt")} desc);
${lockModuleTable(ctx, "deliveries", { read: true })}
${renderPolicy(
  makePolicy({
    table,
    name: ctx.naming.rename("invoice_deliveries_read"),
    command: "select",
    roles: ["authenticated"],
    using: ctx.scope.check(d("tenant"), read),
  }),
  { drop: true, target: table },
)}
`;
}

/** The delivery functions for the module contract. */
export function deliveryContract(
  ctx: BlockSqlContext,
): readonly BlockSqlContractFunction[] {
  if (!hasDeliveries(ctx)) {
    return [];
  }

  return [
    {
      name: "record_invoice_delivery",
      args: ["uuid", "text", "text", "text", "text"],
      returns: "jsonb",
    },
    { name: "list_invoice_deliveries", args: ["uuid"], returns: "jsonb" },
  ];
}

/** `record_invoice_delivery` and `list_invoice_deliveries`. */
export function deliveryFunctions(
  ctx: BlockSqlContext,
  n: InvoiceNames,
): string {
  if (!hasDeliveries(ctx)) {
    return "";
  }

  const { fn, t } = n;
  const i = (column: string): string => ctx.col("invoices", column);
  const d = (column: string): string => ctx.col("deliveries", column);
  const has = (logical: string): boolean => ctx.has("deliveries", logical);

  const can = (permission: string): string =>
    `(${n.service} or ${ctx.scope.can(`x.${i("tenant")}`, permission)})`;

  const json = (row: string): string =>
    `jsonb_build_object('id', ${row}.${d("id")}, 'invoiceId', ${row}.${d("invoice")}, 'channel', ${row}.${d("channel")}, 'format', ${row}.${d("format")}, 'externalRef', ${row}.${d("externalRef")}, 'filename', ${has("filename") ? `${row}.${d("filename")}` : "null::text"}, 'sentAt', ${row}.${d("sentAt")})`;

  return `
-- Keeps the reference a channel returned for an e-invoice. A draft or void
-- invoice is refused; the same channel and reference return the first row.
create or replace function ${fn("record_invoice_delivery")}(invoice uuid, channel text, format text, external_ref text, filename text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_invoice ${t("invoices")};
  v_row ${t("deliveries")};
begin
  select * into v_invoice from ${t("invoices")} x where x.${i("id")} = record_invoice_delivery.invoice and ${can(n.issue)};
  if v_invoice.${i("id")} is null then
    ${fail("INVOICE_NOT_FOUND", "no such invoice you can send", "P0002")}
  end if;
  if ${ctx.is("invoices", "status", `v_invoice.${i("status")}`, ["draft", "void"])} then
    ${fail("EINVOICE_NOT_ISSUED", "a draft or void invoice can't be sent as an e-invoice", "55000")}
  end if;
  if length(coalesce(trim(record_invoice_delivery.channel), '')) not between 1 and 100
    or length(coalesce(trim(record_invoice_delivery.format), '')) not between 1 and 100
    or length(coalesce(trim(record_invoice_delivery.external_ref), '')) not between 1 and 500 then
    ${fail("EINVOICE_DELIVERY_INVALID", "a delivery has a channel, a format and the channel's reference", "22023")}
  end if;
  insert into ${t("deliveries")} (${d("tenant")}, ${d("invoice")}, ${d("channel")}, ${d("format")}, ${d("externalRef")}${has("filename") ? `, ${d("filename")}` : ""}${has("sentBy") ? `, ${d("sentBy")}` : ""})
  values (v_invoice.${i("tenant")}, v_invoice.${i("id")}, trim(record_invoice_delivery.channel), trim(record_invoice_delivery.format), trim(record_invoice_delivery.external_ref)${has("filename") ? ", nullif(trim(record_invoice_delivery.filename), '')" : ""}${has("sentBy") ? ", auth.uid()" : ""})
  on conflict (${d("invoice")}, ${d("channel")}, ${d("externalRef")}) do nothing
  returning * into v_row;
  if v_row.${d("id")} is null then
    select * into v_row from ${t("deliveries")} y
      where y.${d("invoice")} = v_invoice.${i("id")} and y.${d("channel")} = trim(record_invoice_delivery.channel)
        and y.${d("externalRef")} = trim(record_invoice_delivery.external_ref);
  end if;
  return ${json("v_row")};
end;
$$;
${userGrant(`${fn("record_invoice_delivery")}(uuid, text, text, text, text)`)}

-- The e-invoices an invoice was sent as, newest first.
create or replace function ${fn("list_invoice_deliveries")}(invoice uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_invoice ${t("invoices")};
begin
  select * into v_invoice from ${t("invoices")} x where x.${i("id")} = list_invoice_deliveries.invoice and ${can(n.read)};
  if v_invoice.${i("id")} is null then
    ${fail("INVOICE_NOT_FOUND", "no such invoice you can read", "P0002")}
  end if;
  return coalesce((select jsonb_agg(${json("y")} order by y.${d("sentAt")} desc, y.${d("id")})
    from ${t("deliveries")} y where y.${d("invoice")} = v_invoice.${i("id")}), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_invoice_deliveries")}(uuid)`)}
`;
}
