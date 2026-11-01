import type { InvoicesEvents } from "../../blocks/invoices/events.ts";
import type { AccountingSource } from "../accounting-sources-sql.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlTableSpec,
} from "../context.ts";
import type { CollectionHelpers } from "./invoices-collections.ts";
import type { InvoiceNames } from "./invoices-names.ts";

import { bookSource, unbookSource } from "../accounting-sources-sql.ts";
import { hasLegalEntityColumn } from "../numbering-sql.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { fail, transitionActorSql, userGrant } from "../shared.ts";
import { approvalSql, approvalStatusSql } from "./invoices-approval.ts";
import {
  creditCode,
  hasPartyCredit,
  invoiceCollections,
  partyColumns,
} from "./invoices-collections.ts";
import { paymentKey } from "./invoices-ledger.ts";
import { invoiceRepairSql } from "./invoices-repair.ts";
import { lockModuleTable } from "./over-app.ts";

const INVOICE = [
  "organizationId",
  "invoiceId",
  "subjectType",
  "subjectId",
  "identifier",
] as const;

/** The events open items record on an invoice. */
export const OPEN_ITEM_EVENTS: BlockSqlEvents<InvoicesEvents> = {
  "invoice.allocated": {
    subject: "invoices",
    payload: [
      ...INVOICE,
      "reference",
      "paymentId",
      "partyId",
      "amount",
      "discount",
      "balance",
    ],
  },
  "invoice.unallocated": {
    subject: "invoices",
    payload: [...INVOICE, "reference", "amount", "discount", "balance"],
  },
  "invoice.discount_applied": {
    subject: "invoices",
    payload: [...INVOICE, "reference", "paymentId", "discount", "balance"],
  },
};

/**
 * The `invoice_allocations` table: what one payment or credit covered of one
 * invoice, with the early payment discount taken on it.
 */
export const ALLOCATIONS_TABLE: BlockSqlTableSpec = {
  name: "invoice_allocations",
  app: {},
  optionalTable: true,
  lifecycle: { tenant: "tenant", export: true },
  columns: {
    id: "id",
    tenant: "tenant_id",
    reference: "reference",
    party: "party_id",
    invoice: "invoice_id",
    source: "source",
    amount: "amount",
    discount: "discount",
    payment: "payment_id",
    discountPayment: "discount_payment_id",
    allocatedOn: "allocated_on",
    unallocatedAt: "unallocated_at",
    createdBy: "created_by",
    createdAt: "created_at",
  },
};

/** Whether open items and allocations can run on this invoices table. */
function hasOpenItems(ctx: BlockSqlContext): boolean {
  return hasPartyCredit(ctx) && ctx.hasTable("allocations");
}

/** The allocations table, its indexes and its read policy. */
export function allocationTableSql(
  ctx: BlockSqlContext,
  invoices: string,
  invoiceId: string,
  read: string,
): string {
  if (!hasOpenItems(ctx)) {
    return "";
  }

  const table = ctx.table("allocations");
  const a = (column: string): string => ctx.col("allocations", column);

  return `
create table if not exists ${table} (
  ${a("id")} uuid primary key default gen_random_uuid(),
  ${a("tenant")} ${ctx.idType} not null,
  ${a("reference")} text not null check (length(${a("reference")}) between 1 and 200),
  ${a("party")} text not null,
  ${a("invoice")} uuid not null references ${invoices} (${invoiceId}) on delete cascade,
  ${a("source")} text not null default 'payment' check (${a("source")} in ('payment', 'credit')),
  ${a("amount")} bigint not null check (${a("amount")} > 0),
  ${a("discount")} bigint not null default 0 check (${a("discount")} >= 0),
  -- The ledger transactions of the cash (or credit) and of the discount.
  ${a("payment")} uuid,
  ${a("discountPayment")} uuid,
  ${a("allocatedOn")} date not null,
  ${a("unallocatedAt")} timestamptz,
  ${a("createdBy")} uuid,
  ${a("createdAt")} timestamptz not null default now(),
  unique (${a("tenant")}, ${a("reference")}, ${a("invoice")})
);
create index if not exists ${ctx.naming.rename("invoice_allocations_invoice_idx")} on ${table} (${a("invoice")});
create index if not exists ${ctx.naming.rename("invoice_allocations_party_idx")} on ${table} (${a("tenant")}, ${a("party")}, ${a("createdAt")} desc);
${lockModuleTable(ctx, "allocations", { read: true })}
${renderPolicy(
  makePolicy({
    table,
    name: ctx.naming.rename("invoice_allocations_read"),
    command: "select",
    roles: ["authenticated"],
    using: ctx.scope.check(a("tenant"), read),
  }),
  { drop: true, target: table },
)}
`;
}

/**
 * The accounting source of an early payment discount: the receivable against
 * revenue for a sale, the payable against expense for a bill.
 */
export function discountSources(
  ctx: BlockSqlContext,
  party: (alias: string) => string,
): readonly AccountingSource[] {
  if (!hasOpenItems(ctx)) {
    return [];
  }

  const ledger = ctx.of("ledger");
  const tx = (column: string): string => ledger.col("transactions", column);
  const le = (column: string): string => ledger.col("entries", column);
  const la = (column: string): string => ledger.col("accounts", column);
  const i = (column: string): string => ctx.col("invoices", column);
  const purchase = ctx.has("invoices", "direction");

  const isPurchase = purchase ? `inv.${i("direction")} = 'purchase'` : "false";

  return [
    {
      source: "invoice_discount",
      journal: "general",
      fn: "accounting_invoice_discount_lines",
      comment:
        "The entry of an early payment discount for accounting: the receivable against\nrevenue for a sale, the payable against expense for a bill.",
      body: `  select jsonb_build_object(
    'organizationId', y.${tx("tenant")},
    'entryDate', (y.${tx("effectiveAt")} at time zone 'UTC')::date,
    'currency', inv.${i("currency")},
    'reference', inv.${i("identifier")},
    'memo', 'Early payment discount on ' || coalesce(inv.${i("identifier")}, inv.${i("title")}),
    'lines', case when ${isPurchase} then jsonb_build_array(
        jsonb_strip_nulls(jsonb_build_object('role', 'payable', 'debit', d.amount::text, 'partyId', ${party("inv")})),
        jsonb_build_object('role', 'expense', 'credit', d.amount::text, 'description', 'Early payment discount'))
      else jsonb_build_array(
        jsonb_build_object('role', 'revenue', 'debit', d.amount::text, 'description', 'Early payment discount'),
        jsonb_strip_nulls(jsonb_build_object('role', 'receivable', 'credit', d.amount::text, 'partyId', ${party("inv")}))) end
  )
  from ${ledger.table("transactions")} y
  join ${ctx.table("invoices")} inv on inv.${i("id")}::text = y.${tx("metadata")} ->> 'invoiceId'
  cross join lateral (
    select sum(e.${le("amount")}) as amount from ${ledger.table("entries")} e
    join ${ledger.table("accounts")} a on a.${la("id")} = e.${le("account")}
    where e.${le("transaction")} = y.${tx("id")} and a.${la("code")} like 'invoices:discount:%'
  ) d
  where y.${tx("id")}::text = source_id and y.${tx("referenceType")} = 'invoices'
    and y.${tx("kind")} = 'invoice.discount' and d.amount > 0`,
    },
  ];
}

/**
 * Open items per party, `allocate_payment` and `unallocate_payment`, and the
 * ageing buckets.
 */
function openItemsSql(
  ctx: BlockSqlContext,
  n: InvoiceNames,
  h: CollectionHelpers,
  approval: (alias: string) => string,
): string {
  if (!hasOpenItems(ctx)) {
    return "";
  }

  const { fn, t } = n;
  const { i } = h;
  const ledger = ctx.of("ledger");
  const la = (column: string): string => ledger.col("accounts", column);
  const le = (column: string): string => ledger.col("entries", column);
  const tx = (column: string): string => ledger.col("transactions", column);
  const accounts = ledger.table("accounts");
  const entries = ledger.table("entries");
  const transactions = ledger.table("transactions");
  const al = (column: string): string => ctx.col("allocations", column);
  const allocations = ctx.table("allocations");
  const sales = ctx.has("invoices", "direction");

  const early =
    ctx.has("invoices", "discountDueOn") &&
    ctx.has("invoices", "discountAmountEarly");

  const allowed = (tenant: string, permission: string): string =>
    `(${n.service} or ${ctx.scope.can(tenant, permission)})`;

  const ofParty = (alias: string, party: string): string =>
    `(${partyColumns(ctx)
      .map((column) => `${alias}.${i(column)}::text = ${party}`)
      .join(" or ")})`;

  const partyOf = (alias: string): string =>
    `coalesce(${partyColumns(ctx)
      .map((column) => `${alias}.${i(column)}::text`)
      .join(", ")})`;

  const sideOf = (alias: string): string =>
    sales
      ? `case when ${alias}.${i("direction")} = 'purchase' then 'supplier' else 'customer' end`
      : "'customer'";

  const charged = (alias: string): string =>
    ctx.hasTable("charges")
      ? `coalesce((select sum(y.${ctx.col("charges", "amount")}) from ${t("charges")} y where y.${ctx.col("charges", "invoice")} = ${alias}.${i("id")}), 0)`
      : "0";

  // What a credit account holds: the negated balance of its entries.
  const available = (account: string): string =>
    `coalesce(-(select sum(e.${le("amount")}) from ${entries} e where e.${le("account")} = ${account}), 0)`;

  const discountAccount = (
    tenant: string,
    currency: string,
    purchase: string,
  ): string =>
    `${ledger.fn("ledger_account_for")}(${tenant}, 'discount',
      'invoices:discount:' || case when ${purchase} then 'purchase' else 'sales' end || ':' || ${currency},
      'Early payment discount ' || ${currency}, ${currency}, 0::smallint, null, null,
      null, true, ${n.read}, 'invoices', null)`;

  const creditAccount = (
    tenant: string,
    party: string,
    currency: string,
  ): string =>
    `${ledger.fn("ledger_account_for")}(${tenant}, 'credit', ${creditCode(party, currency)},
      'Credit ' || ${party} || ' ' || ${currency}, ${currency}, 0::smallint, 'invoice_party', ${party},
      null, true, ${n.read}, 'invoices', null)`;

  const cashAccount = (tenant: string, currency: string): string =>
    `${ledger.fn("ledger_account_for")}(${tenant}, 'cash', 'invoices:cash:' || ${currency},
      'Invoice payments ' || ${currency}, ${currency}, 0::smallint, null, null,
      null, true, ${n.read}, 'invoices', null)`;

  const earlyTerms = early
    ? `v_early := coalesce(v_row.${i("discountAmountEarly")}, 0);
    v_due := v_row.${i("discountDueOn")};`
    : "v_early := 0;\n    v_due := null;";

  const supplierOnly = sales
    ? ""
    : `
  if v_supplier then
    ${fail("INVOICE_ALLOCATIONS_INVALID", "this invoices table has no purchase bills", "22023")}
  end if;`;

  const direction = (alias: string): string =>
    sales ? ` and (${alias}.${i("direction")} = 'purchase') = v_supplier` : "";

  const paidAsOf = (alias: string): string =>
    `(select coalesce(-sum(e.${le("amount")}), 0)::bigint from ${entries} e
      join ${accounts} a on a.${la("id")} = e.${le("account")}
      join ${transactions} y on y.${tx("id")} = e.${le("transaction")}
      where a.${la("tenant")} = ${alias}.${i("tenant")} and a.${la("code")} = 'invoice:' || ${alias}.${i("id")}::text
        and (y.${tx("effectiveAt")} at time zone 'UTC')::date <= v_as_of)`;

  const entity = hasLegalEntityColumn(ctx, "invoices")
    ? "x.legal_entity_id"
    : "null::uuid";

  const result = (reference: string): string => `jsonb_build_object(
      'reference', ${reference},
      'currency', (select min(x.${i("currency")}::text) from ${t("invoices")} x join ${allocations} b on b.${al("invoice")} = x.${i("id")} where b.${al("tenant")} = v_tenant and b.${al("reference")} = ${reference}),
      'partyId', (select min(b.${al("party")}) from ${allocations} b where b.${al("tenant")} = v_tenant and b.${al("reference")} = ${reference}),
      'allocated', coalesce((select sum(b.${al("amount")}) from ${allocations} b where b.${al("tenant")} = v_tenant and b.${al("reference")} = ${reference} and b.${al("unallocatedAt")} is null), 0)::text,
      'discount', coalesce((select sum(b.${al("discount")}) from ${allocations} b where b.${al("tenant")} = v_tenant and b.${al("reference")} = ${reference} and b.${al("unallocatedAt")} is null), 0)::text,
      'allocations', coalesce((select jsonb_agg(jsonb_build_object('invoiceId', b.${al("invoice")}, 'source', b.${al("source")}, 'amount', b.${al("amount")}::text, 'discount', b.${al("discount")}::text,
          'paymentId', b.${al("payment")}, 'discountPaymentId', b.${al("discountPayment")}, 'allocatedOn', b.${al("allocatedOn")}, 'unallocatedAt', b.${al("unallocatedAt")}) order by b.${al("createdAt")}, b.${al("id")})
        from ${allocations} b where b.${al("tenant")} = v_tenant and b.${al("reference")} = ${reference}), '[]'::jsonb))`;

  return `
-- Everything a party still owes or is owed on an invoice date: open invoices
-- and bills with their balance as of the day (payments dated later don't
-- count), and the party's unallocated payments as negative balances. Each item
-- has a bucket by days past due: current, days1To30, days31To60, days61To90,
-- over90 or unallocated. party_id and side (customer or supplier) narrow it.
-- Credit notes are counted as they stand today.
create or replace function ${fn("open_items_for_party")}(tenant ${ctx.idType}, party_id text default null, as_of date default null, side text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_as_of date := coalesce(open_items_for_party.as_of, current_date);
begin
  if not ${allowed("open_items_for_party.tenant", n.read)} then
    ${fail("INVOICE_FORBIDDEN", "not allowed to read this organization's invoices", "42501")}
  end if;
  if open_items_for_party.side is not null and open_items_for_party.side not in ('customer', 'supplier') then
    ${fail("INVOICE_OPEN_ITEMS_INVALID", "side is customer or supplier", "22023")}
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
        'side', e.side, 'partyId', e.party, 'documentType', e.document_type, 'documentId', e.id,
        'identifier', e.identifier, 'currency', e.currency, 'issuedOn', e.issued_on, 'dueOn', e.due_on,
        'amount', e.gross::text, 'balance', e.balance::text, 'daysOverdue', e.days,
        'bucket', case when e.document_type = 'unallocated_payment' then 'unallocated'
          when e.days <= 0 then 'current' when e.days <= 30 then 'days1To30' when e.days <= 60 then 'days31To60'
          when e.days <= 90 then 'days61To90' else 'over90' end,
        'discountDueOn', e.discount_due_on, 'discountAmount', e.discount_amount::text,
        'legalEntityId', e.entity, 'approvalStatus', e.approval)
      order by e.side, e.party, e.due_on nulls last, e.id)
    from (
      select d.*, case when d.due_on is null then 0 else v_as_of - d.due_on end as days
      from (
        select 'invoice'::text as document_type, x.${i("id")} as id, ${sideOf("x")} as side, ${partyOf("x")} as party,
          x.${i("identifier")}::text as identifier, x.${i("currency")}::text as currency, x.${i("issuedOn")} as issued_on, x.${i("dueOn")} as due_on,
          (x.${i("total")} + ${charged("x")} - x.${i("creditedTotal")})::bigint as gross,
          (x.${i("total")} + ${charged("x")} - x.${i("creditedTotal")} - ${paidAsOf("x")})::bigint as balance,
          ${early ? `x.${i("discountDueOn")}` : "null::date"} as discount_due_on,
          ${early ? `coalesce(x.${i("discountAmountEarly")}, 0)::bigint` : "0::bigint"} as discount_amount,
          ${entity} as entity,
          ${approval("x")} as approval
        from ${t("invoices")} x
        where x.${i("tenant")} = open_items_for_party.tenant
          and ${h.kd(`x.${i("kind")}`, ["invoice"])}
          and ${h.st(`x.${i("status")}`, ["issued", "partially_paid", "paid"])}
          and x.${i("issuedOn")} <= v_as_of
          and (open_items_for_party.party_id is null or ${ofParty("x", "open_items_for_party.party_id")})
        union all
        select 'unallocated_payment'::text, a.${la("id")}, 'customer'::text, a.${la("holderId")}, null::text, a.${la("unit")}::text,
          null::date, null::date, (-c.amount)::bigint, (-c.amount)::bigint, null::date, 0::bigint, null::uuid, null::text
        from ${accounts} a
        cross join lateral (
          select coalesce(-sum(e.${le("amount")}), 0)::bigint as amount from ${entries} e
          join ${transactions} y on y.${tx("id")} = e.${le("transaction")}
          where e.${le("account")} = a.${la("id")} and (y.${tx("effectiveAt")} at time zone 'UTC')::date <= v_as_of
        ) c
        where a.${la("tenant")} = open_items_for_party.tenant and a.${la("managedBy")} = 'invoices'
          and a.${la("holderType")} = 'invoice_party'
          and (open_items_for_party.party_id is null or a.${la("holderId")} = open_items_for_party.party_id)
          and c.amount > 0
      ) d
      where d.balance <> 0
    ) e
    where open_items_for_party.side is null or e.side = open_items_for_party.side
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("open_items_for_party")}(${ctx.idType}, text, date, text)`)}

-- The open items of an organization summed per party and currency in the ageing
-- buckets, with what is outstanding after unallocated payments.
create or replace function ${fn("open_item_ageing")}(tenant ${ctx.idType}, side text default null, as_of date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object('side', k.side, 'partyId', k.party, 'currency', k.currency,
        'current', k.cur::text, 'days1To30', k.d30::text, 'days31To60', k.d60::text, 'days61To90', k.d90::text,
        'over90', k.over::text, 'unallocated', k.unal::text, 'outstanding', k.total::text)
      order by k.side, k.party, k.currency)
    from (
      select r.side, r."partyId" as party, r.currency,
        coalesce(sum(r.balance) filter (where r.bucket = 'current'), 0) as cur,
        coalesce(sum(r.balance) filter (where r.bucket = 'days1To30'), 0) as d30,
        coalesce(sum(r.balance) filter (where r.bucket = 'days31To60'), 0) as d60,
        coalesce(sum(r.balance) filter (where r.bucket = 'days61To90'), 0) as d90,
        coalesce(sum(r.balance) filter (where r.bucket = 'over90'), 0) as over,
        coalesce(sum(r.balance) filter (where r.bucket = 'unallocated'), 0) as unal,
        coalesce(sum(r.balance), 0) as total
      from jsonb_to_recordset(${fn("open_items_for_party")}(open_item_ageing.tenant, null, open_item_ageing.as_of, open_item_ageing.side))
        as r(side text, "partyId" text, currency text, balance bigint, bucket text)
      group by r.side, r."partyId", r.currency
    ) k
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("open_item_ageing")}(${ctx.idType}, text, date)`)}

-- What allocate_payment covered, per payment reference.
create or replace function ${fn("list_invoice_allocations")}(tenant ${ctx.idType}, reference text default null, invoice_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ${allowed("list_invoice_allocations.tenant", n.read)} then
    ${fail("INVOICE_FORBIDDEN", "not allowed to read this organization's invoices", "42501")}
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('currency', (select x.${i("currency")}::text from ${t("invoices")} x where x.${i("id")} = b.${al("invoice")}), 'reference', b.${al("reference")}, 'partyId', b.${al("party")}, 'invoiceId', b.${al("invoice")},
        'source', b.${al("source")}, 'amount', b.${al("amount")}::text, 'discount', b.${al("discount")}::text,
        'paymentId', b.${al("payment")}, 'discountPaymentId', b.${al("discountPayment")},
        'allocatedOn', b.${al("allocatedOn")}, 'unallocatedAt', b.${al("unallocatedAt")}) order by b.${al("createdAt")}, b.${al("id")})
    from ${allocations} b
    where b.${al("tenant")} = list_invoice_allocations.tenant
      and (list_invoice_allocations.reference is null or b.${al("reference")} = list_invoice_allocations.reference)
      and (list_invoice_allocations.invoice_id is null or b.${al("invoice")} = list_invoice_allocations.invoice_id)
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_invoice_allocations")}(${ctx.idType}, text, uuid)`)}

-- Allocates one payment (or party credit) to several invoices or bills.
-- payment: { partyId, side (customer or supplier, default customer), amount,
-- currency, receivedOn, reference, method, note, source (payment or credit) };
-- allocations: [{ invoiceId, amount, takeDiscount (default true) }]. An
-- allocation under the balance is a partial payment. A customer's payment that
-- is more than its allocations leaves the rest as the party's credit; a
-- supplier payment is allocated in full. When the payment arrives by the
-- invoice's discount_due_on and leaves at most discount_amount_early open, the
-- rest is taken as an early payment discount, posted as its own ledger
-- transaction and booked in accounting. source credit draws on the party's
-- credit instead of receiving cash. The reference is required and unique per
-- organization; repeating a call returns what it allocated.
create or replace function ${fn("allocate_payment")}(tenant ${ctx.idType}, payment jsonb, allocations jsonb, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType} := allocate_payment.tenant;
  v_party text := nullif(trim(allocate_payment.payment ->> 'partyId'), '');
  v_side text := coalesce(allocate_payment.payment ->> 'side', 'customer');
  v_supplier boolean;
  v_use_credit boolean := coalesce(allocate_payment.payment ->> 'source', 'payment') = 'credit';
  v_currency text := upper(allocate_payment.payment ->> 'currency');
  v_reference text := nullif(trim(allocate_payment.payment ->> 'reference'), '');
  v_received date;
  v_amount bigint;
  v_allocations jsonb := coalesce(allocate_payment.allocations, '[]'::jsonb);
  v_sum bigint := 0;
  v_remainder bigint := 0;
  v_alloc record;
  v_row ${t("invoices")};
  v_balance bigint;
  v_early bigint;
  v_due date;
  v_discount bigint;
  v_ref text;
  v_pay uuid;
  v_disc uuid;
  v_account uuid;
  v_credit uuid;
  v_was text;
  v_method text := coalesce(nullif(trim(allocate_payment.payment ->> 'method'), ''), 'allocation');
  v_note text := nullif(trim(allocate_payment.payment ->> 'note'), '');
  v_credited bigint := 0;
begin
  if not ${allowed("allocate_payment.tenant", n.payment)} then
    ${fail("INVOICE_FORBIDDEN", "not allowed to record payments in this organization", "42501")}
  end if;
  if jsonb_typeof(allocate_payment.payment) is distinct from 'object' then
    ${fail("INVOICE_ALLOCATIONS_INVALID", "payment is an object of partyId, amount, currency and reference", "22023")}
  end if;
  if v_party is null or length(v_party) > 150 then
    ${fail("INVOICE_PARTY_INVALID", "a party id is a non-empty text of at most 150 characters", "22023")}
  end if;
  if v_side not in ('customer', 'supplier') then
    ${fail("INVOICE_ALLOCATIONS_INVALID", "side is customer or supplier", "22023")}
  end if;
  v_supplier := v_side = 'supplier';${supplierOnly}
  if v_supplier and v_use_credit then
    ${fail("INVOICE_ALLOCATIONS_INVALID", "only a customer's credit is drawn on", "22023")}
  end if;
  if v_currency is null or v_currency !~ '^[A-Z]{3}$' then
    ${fail("INVOICE_CURRENCY_INVALID", "currency is a three-letter ISO 4217 code", "22023")}
  end if;
  if v_reference is null then
    ${fail("INVOICE_PAYMENT_REFERENCE_REQUIRED", "a payment needs a reference, such as the bank transaction id", "22023")}
  end if;
  begin
    v_received := coalesce(nullif(allocate_payment.payment ->> 'receivedOn', '')::date, current_date);
  exception when others then
    ${fail("INVOICE_ALLOCATIONS_INVALID", "receivedOn is a date", "22023")}
  end;
  if not v_use_credit then
    if coalesce(allocate_payment.payment ->> 'amount', '') !~ '^[0-9]{1,18}$' or (allocate_payment.payment ->> 'amount')::bigint = 0 then
      ${fail("INVOICE_PAYMENT_INVALID", "a payment has a positive amount", "22023")}
    end if;
    v_amount := (allocate_payment.payment ->> 'amount')::bigint;
  end if;
  if jsonb_typeof(v_allocations) <> 'array' or jsonb_array_length(v_allocations) = 0 or exists (
    select 1 from jsonb_array_elements(v_allocations) x
    where jsonb_typeof(x.value) <> 'object'
      or coalesce(x.value ->> 'invoiceId', '') !~ '^[0-9a-fA-F-]{36}$'
      or coalesce(x.value ->> 'amount', '') !~ '^[0-9]{1,18}$'
      or (x.value ->> 'amount')::bigint = 0
      or (x.value ? 'takeDiscount' and jsonb_typeof(x.value -> 'takeDiscount') <> 'boolean')
  ) or (
    select count(*) <> count(distinct x.value ->> 'invoiceId') from jsonb_array_elements(v_allocations) x
  ) then
    ${fail("INVOICE_ALLOCATIONS_INVALID", "allocations is a non-empty array of { invoiceId, amount, takeDiscount? } with a positive amount, one per invoice", "22023")}
  end if;
  if exists (select 1 from ${allocations} b where b.${al("tenant")} = v_tenant and b.${al("reference")} = v_reference) then
    if exists (select 1 from ${allocations} b where b.${al("tenant")} = v_tenant and b.${al("reference")} = v_reference and b.${al("unallocatedAt")} is not null) then
      ${fail("INVOICE_ALLOCATION_REFERENCE_USED", "this payment reference was allocated and unallocated; allocate the payment again under a new reference", "55000")}
    end if;
    return ${result("v_reference")} || jsonb_build_object('credited', coalesce((
      select (y.${tx("metadata")} ->> 'amount') from ${transactions} y
      where y.${tx("tenant")} = v_tenant and y.${tx("key")} = 'invoice-party-payment:' || v_reference), '0'));
  end if;
  select coalesce(sum((x.value ->> 'amount')::bigint), 0) into v_sum from jsonb_array_elements(v_allocations) x;
  if v_use_credit then
    v_amount := v_sum;
  elsif v_sum > v_amount then
    ${fail("INVOICE_ALLOCATIONS_TOO_LARGE", "the allocations add up to more than the payment", "23514")}
  end if;
  v_remainder := v_amount - v_sum;
  if v_supplier and v_remainder > 0 then
    ${fail("INVOICE_ALLOCATIONS_REMAINDER", "a supplier payment is allocated in full; lower the payment or allocate the rest", "23514")}
  end if;
  ${transitionActorSql("allocate_payment.actor", "INVOICE_ACTOR_INVALID")}
  for v_alloc in
    select (x.value ->> 'invoiceId')::uuid as invoice, (x.value ->> 'amount')::bigint as amount,
      coalesce((x.value ->> 'takeDiscount')::boolean, true) as take
    from jsonb_array_elements(v_allocations) with ordinality x
    order by x.ordinality
  loop
    select * into v_row from ${t("invoices")} x
    where x.${i("id")} = v_alloc.invoice and x.${i("tenant")} = v_tenant
      and ${ofParty("x", "v_party")}${direction("x")}
    for update;
    if v_row.${i("id")} is null then
      ${fail("INVOICE_NOT_FOUND", "an allocation names no invoice of this party and side", "P0002")}
    end if;
    if ${h.kd(`v_row.${i("kind")}`, ["invoice"], true)} or ${h.st(`v_row.${i("status")}`, ["issued", "partially_paid"], true)} then
      ${fail("INVOICE_NOT_PAYABLE", "only an open invoice takes an allocation", "55000")}
    end if;
    if v_row.${i("currency")}::text <> v_currency then
      ${fail("INVOICE_CURRENCY_MISMATCH", "an allocation must be in the invoice's currency", "22023")}
    end if;
    v_balance := ${h.balance("v_row")};
    if v_alloc.amount > v_balance then
      ${fail("INVOICE_ALLOCATION_TOO_LARGE", "an allocation is more than the invoice's balance", "23514")}
    end if;
    ${earlyTerms}
    v_discount := 0;
    if v_alloc.take and v_early > 0 and v_due is not null and v_received <= v_due
      and v_alloc.amount < v_balance and v_alloc.amount >= v_balance - v_early then
      v_discount := v_balance - v_alloc.amount;
    end if;
    v_ref := v_reference || '/' || v_alloc.invoice::text;
    v_was := v_row.${i("status")};
    if v_use_credit then
      select a.${la("id")} into v_account from ${accounts} a
      where a.${la("tenant")} = v_tenant and a.${la("code")} = ${creditCode("v_party", `v_row.${i("currency")}`)}
      for update;
      if v_account is null or v_alloc.amount > ${available("v_account")} then
        ${fail("INVOICE_CREDIT_INSUFFICIENT", "the party doesn't have this much credit in the invoice's currency", "23514")}
      end if;
      v_pay := ${ledger.fn("ledger_post")}(v_tenant, 'invoice.credit_applied',
        jsonb_build_array(
          jsonb_build_object('account', ${h.ledger.receivable("v_row")}, 'amount', -v_alloc.amount),
          jsonb_build_object('account', v_account, 'amount', v_alloc.amount)),
        'invoices', v_row.${i("id")}::text, null, ${paymentKey("v_ref")}, v_received::timestamptz,
        jsonb_strip_nulls(jsonb_build_object('invoiceId', v_row.${i("id")}, 'method', 'credit', 'partyId', v_party, 'reference', v_ref)));${h.settle("v_row")}
    else
      perform ${fn("record_invoice_payment")}(v_row.${i("id")}, v_alloc.amount, v_currency, v_received::timestamptz,
        v_method, v_ref, v_note, allocate_payment.actor, null);
      select y.${tx("id")} into v_pay from ${transactions} y where y.${tx("tenant")} = v_tenant and y.${tx("key")} = ${paymentKey("v_ref")};
      select * into v_row from ${t("invoices")} x where x.${i("id")} = v_alloc.invoice;
    end if;
    if v_discount > 0 then
      v_disc := ${ledger.fn("ledger_post")}(v_tenant, 'invoice.discount',
        jsonb_build_array(
          jsonb_build_object('account', ${h.ledger.receivable("v_row")}, 'amount', -v_discount),
          jsonb_build_object('account', ${discountAccount("v_tenant", `v_row.${i("currency")}::text`, sales ? `v_row.${i("direction")} = 'purchase'` : "false")}, 'amount', v_discount)),
        'invoices', v_row.${i("id")}::text, null, 'invoice-discount:' || v_ref, v_received::timestamptz,
        jsonb_strip_nulls(jsonb_build_object('invoiceId', v_row.${i("id")}, 'method', 'early_payment_discount', 'reference', v_ref, 'partyId', v_party)));${h.settle("v_row")}
      ${bookSource(ctx, "invoice_discount", "v_disc")}
      ${h.record("invoice.discount_applied", "v_row", `, 'reference', v_reference, 'paymentId', v_disc, 'discount', v_discount::text, 'balance', ${h.balance("v_row")}::text`, true)}
    else
      v_disc := null;
    end if;
    insert into ${allocations} (${al("tenant")}, ${al("reference")}, ${al("party")}, ${al("invoice")}, ${al("source")}, ${al("amount")}, ${al("discount")}, ${al("payment")}, ${al("discountPayment")}, ${al("allocatedOn")}, ${al("createdBy")})
    values (v_tenant, v_reference, v_party, v_row.${i("id")}, case when v_use_credit then 'credit' else 'payment' end, v_alloc.amount, v_discount, v_pay, v_disc, v_received, auth.uid());
    ${h.record("invoice.allocated", "v_row", `, 'reference', v_reference, 'paymentId', v_pay, 'partyId', v_party, 'amount', v_alloc.amount::text, 'discount', v_discount::text, 'balance', ${h.balance("v_row")}::text`, true)}
    if ${h.st(`v_row.${i("status")}`, ["paid"])} and ${h.st("v_was", ["paid"], true)} and (v_use_credit or v_discount > 0) then
      ${h.record("invoice.paid", "v_row", `, 'total', v_row.${i("total")}::text`)}
    end if;
  end loop;
  if v_remainder > 0 then
    v_credit := ${ledger.fn("ledger_post")}(v_tenant, 'invoice.party_payment',
      jsonb_build_array(
        jsonb_build_object('account', ${cashAccount("v_tenant", "v_currency")}, 'amount', v_remainder),
        jsonb_build_object('account', ${creditAccount("v_tenant", "v_party", "v_currency")}, 'amount', -v_remainder)),
      'invoices', v_party, null, 'invoice-party-payment:' || v_reference, v_received::timestamptz,
      jsonb_strip_nulls(jsonb_build_object('partyId', v_party, 'currency', v_currency, 'method', v_method,
        'reference', v_reference, 'note', v_note, 'amount', v_remainder::text)));
    ${bookSource(ctx, "invoice_party_payment", "v_credit")}
    v_credited := v_remainder;
  end if;
  return ${result("v_reference")} || jsonb_build_object('credited', v_credited::text);
end;
$$;
${userGrant(`${fn("allocate_payment")}(${ctx.idType}, jsonb, jsonb, jsonb)`)}

-- Undoes allocate_payment for a reference: each cash payment, credit draw and
-- discount of it is reversed on the ledger, so the invoices reopen with their
-- balance and the credit is restored. The unallocated rest of a customer
-- payment stays the party's credit, and a reference can't be allocated again.
-- Needs the permission to reverse payments.
create or replace function ${fn("unallocate_payment")}(tenant ${ctx.idType}, reference text, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType} := unallocate_payment.tenant;
  v_alloc ${allocations}%rowtype;
  v_row ${t("invoices")};
  v_reversal uuid;
  v_count integer := 0;
begin
  if not ${allowed("unallocate_payment.tenant", n.reverse)} then
    ${fail("INVOICE_FORBIDDEN", "not allowed to reverse payments in this organization", "42501")}
  end if;
  ${transitionActorSql("unallocate_payment.actor", "INVOICE_ACTOR_INVALID")}
  for v_alloc in
    select * from ${allocations} b
    where b.${al("tenant")} = v_tenant and b.${al("reference")} = unallocate_payment.reference and b.${al("unallocatedAt")} is null
    order by b.${al("createdAt")} desc, b.${al("id")}
    for update
  loop
    if v_alloc.${al("discountPayment")} is not null then
      select * into v_row from ${t("invoices")} x where x.${i("id")} = v_alloc.${al("invoice")} for update;
      v_reversal := ${h.ledger.reverse("v_row", `v_alloc.${al("discountPayment")}`, "'Unallocated'")};${h.settle("v_row")}
      ${unbookSource(ctx, "invoice_discount", `v_row.${i("tenant")}`, `v_alloc.${al("discountPayment")}`)}
    end if;
    if v_alloc.${al("source")} = 'credit' then
      select * into v_row from ${t("invoices")} x where x.${i("id")} = v_alloc.${al("invoice")} for update;
      v_reversal := ${h.ledger.reverse("v_row", `v_alloc.${al("payment")}`, "'Unallocated'")};${h.settle("v_row")}
    else
      perform ${fn("reverse_invoice_payment")}(v_alloc.${al("payment")}, 'Unallocated', unallocate_payment.actor);
    end if;
    update ${allocations} b set ${al("unallocatedAt")} = now() where b.${al("id")} = v_alloc.${al("id")};
    select * into v_row from ${t("invoices")} x where x.${i("id")} = v_alloc.${al("invoice")};
    ${h.record("invoice.unallocated", "v_row", `, 'reference', unallocate_payment.reference, 'amount', v_alloc.${al("amount")}::text, 'discount', v_alloc.${al("discount")}::text, 'balance', ${h.balance("v_row")}::text`, true)}
    v_count := v_count + 1;
  end loop;
  if v_count = 0 then
    ${fail("INVOICE_ALLOCATION_NOT_FOUND", "no allocation with this reference is active", "P0002")}
  end if;
  return jsonb_build_object('reference', unallocate_payment.reference, 'unallocated', v_count);
end;
$$;
${userGrant(`${fn("unallocate_payment")}(${ctx.idType}, text, jsonb)`)}
`;
}

/** The contract of the open item functions. */
export function openItemContract(
  ctx: BlockSqlContext,
): readonly BlockSqlContractFunction[] {
  if (!hasOpenItems(ctx)) {
    return [];
  }

  return [
    {
      name: "open_items_for_party",
      args: ["{id}", "text", "date", "text"],
      returns: "jsonb",
    },
    {
      name: "open_item_ageing",
      args: ["{id}", "text", "date"],
      returns: "jsonb",
    },
    {
      name: "list_invoice_allocations",
      args: ["{id}", "text", "uuid"],
      returns: "jsonb",
    },
    {
      name: "allocate_payment",
      args: ["{id}", "jsonb", "jsonb", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "unallocate_payment",
      args: ["{id}", "text", "jsonb"],
      returns: "jsonb",
    },
  ];
}

/**
 * Collections, approval and open items: the invoices functions that follow the
 * core ones.
 */
export function invoiceCollectionsAndOpenItems(
  ctx: BlockSqlContext,
  n: InvoiceNames,
  h: CollectionHelpers,
): string {
  return `${invoiceCollections(ctx, n, h)}${approvalSql(ctx, n, h)}${openItemsSql(ctx, n, h, (alias) => approvalStatusSql(ctx, n, alias))}${invoiceRepairSql(ctx, n, h)}`;
}
