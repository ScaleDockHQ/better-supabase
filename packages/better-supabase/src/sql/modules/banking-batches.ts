import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlTableSpec,
} from "../context.ts";

import { sqlIdent } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { lockTable, pageSize, userGrant } from "../shared.ts";
import { bankingSql, linked } from "./banking-sql.ts";

/** Where a payment batch stands. */
export const BATCH_STATUSES = [
  "draft",
  "posted",
  "reconciled",
  "cancelled",
] as const;

/** Where one payment of a batch stands. */
export const BATCH_ITEM_STATUSES = [
  "open",
  "posted",
  "paid",
  "cancelled",
] as const;

/** The reference prefix of the allocation a reconciled batch records. */
const BATCH_REFERENCE = "payment-batch:";

/** The `payment_batches` table: a SEPA credit transfer file of supplier bills. */
export const BATCHES_TABLE: BlockSqlTableSpec = {
  name: "payment_batches",
  app: {},
  optionalTable: true,
  lifecycle: { tenant: "tenant", export: true },
  columns: {
    id: "id",
    tenant: "tenant_id",
    account: "bank_account_id",
    reference: "reference",
    messageId: "message_id",
    currency: "currency",
    dueBy: "due_by",
    executionOn: "execution_on",
    total: "total",
    itemCount: "item_count",
    status: "status",
    transaction: "bank_transaction_id",
    createdBy: "created_by",
    createdAt: "created_at",
    postedAt: "posted_at",
    reconciledAt: "reconciled_at",
  },
  optional: ["transaction", "createdBy", "postedAt", "reconciledAt"],
};

/** The `payment_batch_items` table: one bill paid by a batch. */
export const BATCH_ITEMS_TABLE: BlockSqlTableSpec = {
  name: "payment_batch_items",
  app: {},
  optionalTable: true,
  lifecycle: { tenant: "tenant", export: true },
  columns: {
    id: "id",
    tenant: "tenant_id",
    batch: "batch_id",
    invoice: "invoice_id",
    party: "party_id",
    creditorName: "creditor_name",
    creditorIban: "creditor_iban",
    creditorBic: "creditor_bic",
    amount: "amount",
    discount: "discount",
    currency: "currency",
    endToEndId: "end_to_end_id",
    remittance: "remittance",
    status: "status",
  },
  optional: ["creditorBic", "remittance"],
};

/**
 * Whether payment batches can run: the invoices block with open items and
 * purchase bills is installed, and the batch tables are on.
 */
export function hasBatches(ctx: BlockSqlContext): boolean {
  const invoices = linked(ctx, "invoices");

  return (
    invoices !== undefined &&
    ctx.hasTable("batches") &&
    ctx.hasTable("batchItems") &&
    invoices.hasTable("allocations") &&
    invoices.has("invoices", "direction") &&
    invoices.has("invoices", "dueOn") &&
    invoices.has("invoices", "identifier")
  );
}

const list = (values: readonly string[]): string =>
  values.map((value) => `'${value}'`).join(", ");

/** The batch and item tables with their indexes and read policies. */
export function batchTablesSql(ctx: BlockSqlContext): string {
  const invoices = linked(ctx, "invoices");

  if (!hasBatches(ctx) || !invoices) {
    return "";
  }

  const q = bankingSql(ctx);
  const { a, t } = q;
  const b = (column: string): string => ctx.col("batches", column);
  const p = (column: string): string => ctx.col("batchItems", column);
  const batches = ctx.table("batches");
  const items = ctx.table("batchItems");

  const name = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  const readPolicy = (logical: string, tenant: string): string =>
    renderPolicy(
      makePolicy({
        table: ctx.table(logical),
        name: name(logical, "read"),
        command: "select",
        roles: ["authenticated"],
        using: ctx.scope.check(tenant, q.read),
      }),
      { drop: true, target: ctx.table(logical) },
    );

  const invoiceRef = invoices.owns("invoices")
    ? ` references ${invoices.table("invoices")} (${invoices.col("invoices", "id")}) on delete restrict`
    : "";

  return `
create table if not exists ${batches} (
  ${b("id")} uuid primary key default gen_random_uuid(),
  ${b("tenant")} ${ctx.idType} not null,
  ${b("account")} uuid not null,
  ${b("reference")} text not null check (length(${b("reference")}) between 1 and 200),
  -- The SEPA MsgId of the file: at most 35 characters.
  ${b("messageId")} text not null check (length(${b("messageId")}) between 1 and 35),
  ${b("currency")} char(3) not null check (${b("currency")} ~ '^[A-Z]{3}$'),
  ${b("dueBy")} date not null,
  ${b("executionOn")} date not null,
  -- Minor units paid out: the bills' balances less the discounts taken.
  ${b("total")} bigint not null check (${b("total")} > 0),
  ${b("itemCount")} integer not null check (${b("itemCount")} > 0),
  ${b("status")} text not null default 'draft' check (${b("status")} in (${list(BATCH_STATUSES)})),
  -- The bank transaction that reconciled it.
  ${b("transaction")} uuid,
  ${b("createdBy")} uuid,
  ${b("createdAt")} timestamptz not null default now(),
  ${b("postedAt")} timestamptz,
  ${b("reconciledAt")} timestamptz,
  unique (${b("tenant")}, ${b("id")}),
  unique (${b("tenant")}, ${b("reference")}),
  foreign key (${b("tenant")}, ${b("account")}) references ${q.accounts} (${a("tenant")}, ${a("id")}) on delete restrict,
  foreign key (${b("tenant")}, ${b("transaction")}) references ${q.transactions} (${t("tenant")}, ${t("id")}) on delete set null (${b("transaction")})
);
create index if not exists ${name("batches", "tenant_idx")} on ${batches} (${b("tenant")}, ${b("status")}, ${b("createdAt")});
create index if not exists ${name("batches", "account_idx")} on ${batches} (${b("tenant")}, ${b("account")});
create index if not exists ${name("batches", "transaction_idx")} on ${batches} (${b("tenant")}, ${b("transaction")});
${lockTable(batches, { read: true })}
${readPolicy("batches", b("tenant"))}

create table if not exists ${items} (
  ${p("id")} uuid primary key default gen_random_uuid(),
  ${p("tenant")} ${ctx.idType} not null,
  ${p("batch")} uuid not null,
  ${p("invoice")} uuid not null${invoiceRef},
  ${p("party")} text not null,
  ${p("creditorName")} text not null check (length(${p("creditorName")}) between 1 and 140),
  ${p("creditorIban")} text not null check (${p("creditorIban")} ~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$'),
  ${p("creditorBic")} text check (${p("creditorBic")} is null or ${p("creditorBic")} ~ '^[A-Z]{6}[A-Z0-9]{2}([A-Z0-9]{3})?$'),
  -- Minor units paid for the bill, and the early payment discount it takes.
  ${p("amount")} bigint not null check (${p("amount")} > 0),
  ${p("discount")} bigint not null default 0 check (${p("discount")} >= 0),
  ${p("currency")} char(3) not null check (${p("currency")} ~ '^[A-Z]{3}$'),
  -- The SEPA EndToEndId: at most 35 characters.
  ${p("endToEndId")} text not null check (length(${p("endToEndId")}) between 1 and 35),
  ${p("remittance")} text check (${p("remittance")} is null or length(${p("remittance")}) <= 140),
  ${p("status")} text not null default 'open' check (${p("status")} in (${list(BATCH_ITEM_STATUSES)})),
  foreign key (${p("tenant")}, ${p("batch")}) references ${batches} (${b("tenant")}, ${b("id")}) on delete cascade
);
create index if not exists ${name("batchItems", "parent_idx")} on ${items} (${p("tenant")}, ${p("batch")});
-- A bill sits in at most one live batch.
create index if not exists ${name("batchItems", "invoice_idx")} on ${items} (${p("invoice")});
create unique index if not exists ${name("batchItems", "invoice_key")} on ${items} (${p("invoice")}) where ${p("status")} in ('open', 'posted');
${lockTable(items, { read: true })}
${readPolicy("batchItems", p("tenant"))}
`;
}

/**
 * The SQL that settles (or undoes) a match of `v_match` to a payment batch of
 * the transaction `v_row`: each supplier's bills are paid with one allocation,
 * the batch is reconciled and its items are paid. The matching function
 * declares `v_batch` and `v_group`.
 */
export function batchSettle(ctx: BlockSqlContext, undo: boolean): string {
  const invoices = linked(ctx, "invoices");

  if (!hasBatches(ctx) || !invoices) {
    return "";
  }

  const q = bankingSql(ctx);
  const { m, t } = q;
  const b = (column: string): string => ctx.col("batches", column);
  const p = (column: string): string => ctx.col("batchItems", column);
  const batches = ctx.table("batches");
  const items = ctx.table("batchItems");

  if (undo) {
    return `if v_match.${m("targetType")} = 'payment_batch' then
      select * into v_batch from ${batches} x where x.${b("id")} = v_match.${m("targetId")} and x.${b("tenant")} = v_row.${t("tenant")};
      if found and v_batch.${b("status")} = 'reconciled' then
        for v_group in select distinct y.${p("party")} as party from ${items} y where y.${p("batch")} = v_batch.${b("id")} and y.${p("status")} = 'paid' loop
          perform ${invoices.fn("unallocate_payment")}(v_row.${t("tenant")}, '${BATCH_REFERENCE}' || v_batch.${b("id")}::text || ':' || v_group.party, null);
        end loop;
        update ${items} y set ${p("status")} = 'posted' where y.${p("batch")} = v_batch.${b("id")} and y.${p("status")} = 'paid';
        update ${batches} y set ${b("status")} = 'posted', ${b("transaction")} = null, ${b("reconciledAt")} = null where y.${b("id")} = v_batch.${b("id")};
      end if;`;
  }

  return `if v_match.${m("targetType")} = 'payment_batch' then
      select * into v_batch from ${batches} x
      where x.${b("id")} = v_match.${m("targetId")} and x.${b("tenant")} = v_row.${t("tenant")} for update;
      if not found or v_batch.${b("status")} <> 'posted'
        or v_batch.${b("account")} <> v_row.${t("account")} or v_batch.${b("currency")} <> v_row.${t("currency")}
        or -v_match.${m("amount")} <> v_batch.${b("total")} then
        ${q.matchInvalid("the match must name a posted payment batch of the account and currency, for its total")}
      end if;
      for v_group in
        select y.${p("party")} as party, sum(y.${p("amount")})::bigint as amount,
          jsonb_agg(jsonb_build_object('invoiceId', y.${p("invoice")}, 'amount', y.${p("amount")}::text) order by y.${p("id")}) as allocations
        from ${items} y where y.${p("batch")} = v_batch.${b("id")} and y.${p("status")} = 'posted'
        group by y.${p("party")} order by y.${p("party")}
      loop
        perform ${invoices.fn("allocate_payment")}(v_row.${t("tenant")}, jsonb_build_object('partyId', v_group.party, 'side', 'supplier',
          'amount', v_group.amount::text, 'currency', v_row.${t("currency")}, 'receivedOn', v_row.${t("bookedOn")},
          'reference', '${BATCH_REFERENCE}' || v_batch.${b("id")}::text || ':' || v_group.party, 'method', 'sepa_credit_transfer',
          'note', left(v_batch.${b("reference")}, 500)), v_group.allocations, null);
      end loop;
      update ${items} y set ${p("status")} = 'paid' where y.${p("batch")} = v_batch.${b("id")} and y.${p("status")} = 'posted';
      update ${batches} y set ${b("status")} = 'reconciled', ${b("transaction")} = v_row.${t("id")}, ${b("reconciledAt")} = now() where y.${b("id")} = v_batch.${b("id")};`;
}

/** Creating, reading, posting and cancelling payment batches. */
export function batchFunctions(ctx: BlockSqlContext): string {
  const invoices = linked(ctx, "invoices");

  if (!hasBatches(ctx) || !invoices) {
    return "";
  }

  const q = bankingSql(ctx);
  const { a } = q;
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const b = (column: string): string => ctx.col("batches", column);
  const p = (column: string): string => ctx.col("batchItems", column);
  const batches = ctx.table("batches");
  const items = ctx.table("batchItems");

  const approval =
    invoices.hasTable("approvals") && invoices.hasTable("approvalLevels");

  const invalid = (message: string): string =>
    `raise exception '${message}' using errcode = '22023', hint = 'PAYMENT_BATCH_INVALID';`;

  const batchJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${b("id")}, 'organizationId', ${row}.${b("tenant")}, 'accountId', ${row}.${b("account")}, 'reference', ${row}.${b("reference")}, 'messageId', ${row}.${b("messageId")}, 'currency', ${row}.${b("currency")}, 'dueBy', ${row}.${b("dueBy")}, 'executionOn', ${row}.${b("executionOn")}, 'total', ${row}.${b("total")}::text, 'itemCount', ${row}.${b("itemCount")}, 'status', ${row}.${b("status")}, 'transactionId', ${row}.${b("transaction")}, 'createdBy', ${row}.${b("createdBy")}, 'createdAt', ${row}.${b("createdAt")}, 'postedAt', ${row}.${b("postedAt")}, 'reconciledAt', ${row}.${b("reconciledAt")}, 'items', coalesce((select jsonb_agg(jsonb_build_object('id', y.${p("id")}, 'invoiceId', y.${p("invoice")}, 'partyId', y.${p("party")}, 'creditorName', y.${p("creditorName")}, 'creditorIban', y.${p("creditorIban")}, 'creditorBic', y.${p("creditorBic")}, 'amount', y.${p("amount")}::text, 'discount', y.${p("discount")}::text, 'currency', y.${p("currency")}, 'endToEndId', y.${p("endToEndId")}, 'remittance', y.${p("remittance")}, 'status', y.${p("status")}) order by y.${p("creditorName")}, y.${p("id")}) from ${items} y where y.${p("batch")} = ${row}.${b("id")}), '[]'::jsonb))`;

  const approvalGate = approval
    ? `
    if coalesce(${invoices.fn("invoice_approval_state")}(v_item.invoice_id) ->> 'status', 'not_required') = 'pending' then
      raise exception 'a bill in the batch still needs approval' using errcode = '55000', hint = 'PAYMENT_BATCH_APPROVAL_REQUIRED',
        detail = jsonb_build_object('invoiceId', v_item.invoice_id)::text;
    end if;`
    : "";

  const eligible = approval
    ? `
      and (v_ids is not null or coalesce(r."approvalStatus", 'not_required') <> 'pending')`
    : "";

  return `
-- Selects the approved open supplier bills due by a date and writes them as a
-- draft payment batch of one bank account. input: { accountId, dueBy,
-- executionOn (default today), reference, invoiceIds (only these bills),
-- creditors: { "<partyId>": { name, iban, bic? } } }. A bill with an early
-- payment discount still open on the execution date is paid less the discount,
-- and is selected when its discount date falls by dueBy even if it is due later.
-- Bills that wait for approval are left out; naming one refuses the batch.
create or replace function ${fn("create_payment_batch")}(tenant ${idType}, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_account ${q.accounts}%rowtype;
  v_batch ${batches}%rowtype;
  v_due date;
  v_exec date;
  v_reference text;
  v_ids uuid[];
  v_item record;
  v_creditor jsonb;
  v_iban text;
  v_total bigint := 0;
  v_count integer := 0;
begin
  if not ${q.allowed("create_payment_batch.tenant", q.reconcile)} then
    ${q.forbidden("not allowed to create payment batches")}
  end if;
  if jsonb_typeof(create_payment_batch.input) is distinct from 'object'
    or coalesce(create_payment_batch.input ->> 'accountId', '') !~ '^[0-9a-fA-F-]{36}$'
    or coalesce(create_payment_batch.input ->> 'dueBy', '') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
    or jsonb_typeof(create_payment_batch.input -> 'creditors') is distinct from 'object' then
    ${invalid("input needs accountId, dueBy and creditors")}
  end if;
  select * into v_account from ${q.accounts} x
  where x.${a("id")} = (create_payment_batch.input ->> 'accountId')::uuid and x.${a("tenant")} = create_payment_batch.tenant and x.${a("archivedAt")} is null;
  if not found then
    ${q.accountMissing}
  end if;
  if v_account.${a("iban")} is null then
    ${invalid("the bank account needs an IBAN to pay from")}
  end if;
  v_due := (create_payment_batch.input ->> 'dueBy')::date;
  v_exec := coalesce((create_payment_batch.input ->> 'executionOn')::date, current_date);
  v_reference := coalesce(nullif(trim(create_payment_batch.input ->> 'reference'), ''), 'Batch ' || to_char(v_exec, 'YYYY-MM-DD') || ' ' || left(gen_random_uuid()::text, 8));
  if jsonb_typeof(create_payment_batch.input -> 'invoiceIds') = 'array' then
    select array_agg(x.value::uuid) into v_ids from jsonb_array_elements_text(create_payment_batch.input -> 'invoiceIds') x;
  end if;
  insert into ${batches} (${b("tenant")}, ${b("account")}, ${b("reference")}, ${b("messageId")}, ${b("currency")}, ${b("dueBy")}, ${b("executionOn")}, ${b("total")}, ${b("itemCount")}, ${b("createdBy")})
  values (create_payment_batch.tenant, v_account.${a("id")}, v_reference, 'BSB' || replace(gen_random_uuid()::text, '-', ''), v_account.${a("currency")}, v_due, v_exec, 1, 1, auth.uid())
  returning * into v_batch;
  for v_item in
    select r."documentId" as invoice_id, r."partyId" as party, r.identifier, r.balance::bigint as balance,
      r."discountDueOn" as discount_due_on, coalesce(r."discountAmount", 0)::bigint as discount_amount
    from jsonb_to_recordset(${invoices.fn("open_items_for_party")}(create_payment_batch.tenant, null, current_date, 'supplier'))
      as r("documentType" text, "documentId" uuid, "partyId" text, identifier text, currency text, "dueOn" date, balance bigint,
        "discountDueOn" date, "discountAmount" bigint, "approvalStatus" text)
    where r."documentType" = 'invoice' and r.currency = v_account.${a("currency")} and r.balance > 0
      and (v_ids is null or r."documentId" = any (v_ids))${eligible}
      and (r."dueOn" <= v_due or (r."discountDueOn" is not null and r."discountDueOn" >= v_exec and r."discountDueOn" <= v_due and r."discountAmount" > 0))
      and not exists (select 1 from ${items} y where y.${p("invoice")} = r."documentId" and y.${p("status")} in ('open', 'posted'))
    order by r."partyId", r."dueOn", r."documentId"
  loop${approvalGate}
    v_creditor := create_payment_batch.input -> 'creditors' -> v_item.party;
    if jsonb_typeof(v_creditor) is distinct from 'object' or coalesce(trim(v_creditor ->> 'name'), '') = '' then
      raise exception 'a creditor is missing for a supplier in the batch' using errcode = '22023', hint = 'PAYMENT_BATCH_CREDITOR_MISSING',
        detail = jsonb_build_object('partyId', v_item.party)::text;
    end if;
    v_iban := upper(regexp_replace(coalesce(v_creditor ->> 'iban', ''), '\\s', '', 'g'));
    if v_iban !~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$' or ${fn("bank_mod97")}(substr(v_iban, 5) || substr(v_iban, 1, 4)) is distinct from 1 then
      raise exception 'a creditor has an invalid IBAN' using errcode = '22023', hint = 'PAYMENT_BATCH_CREDITOR_INVALID',
        detail = jsonb_build_object('partyId', v_item.party)::text;
    end if;
    insert into ${items} (${p("tenant")}, ${p("batch")}, ${p("invoice")}, ${p("party")}, ${p("creditorName")}, ${p("creditorIban")}, ${p("creditorBic")}, ${p("amount")}, ${p("discount")}, ${p("currency")}, ${p("endToEndId")}, ${p("remittance")})
    values (create_payment_batch.tenant, v_batch.${b("id")}, v_item.invoice_id, v_item.party, left(trim(v_creditor ->> 'name'), 140), v_iban,
      nullif(upper(regexp_replace(coalesce(v_creditor ->> 'bic', ''), '\\s', '', 'g')), ''),
      v_item.balance - case when v_item.discount_due_on >= v_exec then v_item.discount_amount else 0 end,
      case when v_item.discount_due_on >= v_exec then v_item.discount_amount else 0 end,
      v_account.${a("currency")}, replace(gen_random_uuid()::text, '-', ''), left(v_item.identifier, 140));
    v_total := v_total + v_item.balance - case when v_item.discount_due_on >= v_exec then v_item.discount_amount else 0 end;
    v_count := v_count + 1;
  end loop;
  if v_count = 0 then
    raise exception 'no approved open bill is due by that date' using errcode = '22023', hint = 'PAYMENT_BATCH_EMPTY';
  end if;
  update ${batches} y set ${b("total")} = v_total, ${b("itemCount")} = v_count where y.${b("id")} = v_batch.${b("id")} returning * into v_batch;
  return ${batchJson("v_batch")};
end;
$$;
${userGrant(`${fn("create_payment_batch")}(${idType}, jsonb)`)}

-- A payment batch with its items.
create or replace function ${fn("get_payment_batch")}(batch_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_batch ${batches}%rowtype;
begin
  select * into v_batch from ${batches} x where x.${b("id")} = get_payment_batch.batch_id;
  if not found or not ${q.allowed(`v_batch.${b("tenant")}`, q.read)} then
    raise exception 'no such payment batch' using errcode = 'P0002', hint = 'PAYMENT_BATCH_NOT_FOUND';
  end if;
  return ${batchJson("v_batch")};
end;
$$;
${userGrant(`${fn("get_payment_batch")}(uuid)`)}

-- Payment batches of an organization, newest first, optionally of one status.
create or replace function ${fn("list_payment_batches")}(tenant ${idType}, status text default null, page_size integer default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ${q.allowed("list_payment_batches.tenant", q.read)} then
    ${q.forbidden("not allowed to read payment batches")}
  end if;
  return coalesce((
    select jsonb_agg(${batchJson("k")} order by k.${b("createdAt")} desc, k.${b("id")})
    from (
      select * from ${batches} x
      where x.${b("tenant")} = list_payment_batches.tenant and (list_payment_batches.status is null or x.${b("status")} = list_payment_batches.status)
      order by x.${b("createdAt")} desc, x.${b("id")}
      limit ${pageSize("list_payment_batches.page_size", 50, 200)}
    ) k
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_payment_batches")}(${idType}, text, integer)`)}

-- Posts a draft batch: its bills count as paid, pending the bank's
-- confirmation. Bills that still need approval refuse the post. Reconciling the
-- bank transaction (a match of target type payment_batch) closes the items.
create or replace function ${fn("post_payment_batch")}(batch_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_batch ${batches}%rowtype;
  v_item record;
begin
  select * into v_batch from ${batches} x where x.${b("id")} = post_payment_batch.batch_id for update;
  if not found or not ${q.allowed(`v_batch.${b("tenant")}`, q.reconcile)} then
    raise exception 'no such payment batch' using errcode = 'P0002', hint = 'PAYMENT_BATCH_NOT_FOUND';
  end if;
  if v_batch.${b("status")} <> 'draft' then
    raise exception 'only a draft batch is posted' using errcode = '55000', hint = 'PAYMENT_BATCH_STATUS_INVALID',
      detail = jsonb_build_object('status', v_batch.${b("status")})::text;
  end if;
  for v_item in select y.${p("invoice")} as invoice_id from ${items} y where y.${p("batch")} = v_batch.${b("id")} loop${approvalGate}
  end loop;
  update ${items} y set ${p("status")} = 'posted' where y.${p("batch")} = v_batch.${b("id")} and y.${p("status")} = 'open';
  update ${batches} y set ${b("status")} = 'posted', ${b("postedAt")} = now() where y.${b("id")} = v_batch.${b("id")} returning * into v_batch;
  return ${batchJson("v_batch")};
end;
$$;
${userGrant(`${fn("post_payment_batch")}(uuid)`)}

-- Cancels a draft or posted batch, freeing its bills for another one. A
-- reconciled batch is undone by unmatching its bank transaction first.
create or replace function ${fn("cancel_payment_batch")}(batch_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_batch ${batches}%rowtype;
begin
  select * into v_batch from ${batches} x where x.${b("id")} = cancel_payment_batch.batch_id for update;
  if not found or not ${q.allowed(`v_batch.${b("tenant")}`, q.reconcile)} then
    raise exception 'no such payment batch' using errcode = 'P0002', hint = 'PAYMENT_BATCH_NOT_FOUND';
  end if;
  if v_batch.${b("status")} not in ('draft', 'posted') then
    raise exception 'only a draft or posted batch is cancelled' using errcode = '55000', hint = 'PAYMENT_BATCH_STATUS_INVALID',
      detail = jsonb_build_object('status', v_batch.${b("status")})::text;
  end if;
  update ${items} y set ${p("status")} = 'cancelled' where y.${p("batch")} = v_batch.${b("id")};
  update ${batches} y set ${b("status")} = 'cancelled' where y.${b("id")} = v_batch.${b("id")} returning * into v_batch;
  return ${batchJson("v_batch")};
end;
$$;
${userGrant(`${fn("cancel_payment_batch")}(uuid)`)}
`;
}

/** The contract of the batch functions. */
export function batchContract(
  ctx: BlockSqlContext,
): readonly BlockSqlContractFunction[] {
  if (!hasBatches(ctx)) {
    return [];
  }

  return [
    { name: "create_payment_batch", args: ["{id}", "jsonb"], returns: "jsonb" },
    { name: "get_payment_batch", args: ["uuid"], returns: "jsonb" },
    {
      name: "list_payment_batches",
      args: ["{id}", "text", "integer"],
      returns: "jsonb",
    },
    { name: "post_payment_batch", args: ["uuid"], returns: "jsonb" },
    { name: "cancel_payment_batch", args: ["uuid"], returns: "jsonb" },
  ];
}
