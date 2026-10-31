import type { BlockSqlContext } from "../context.ts";

import { ledgerRebalance, ledgerTables } from "./ledger.ts";
import { moduleOperations } from "./permissions-model.ts";

/** The code of an invoice's receivable account. */
const receivableCode = (invoice: string): string =>
  `'invoice:' || ${invoice}::text`;

/** The code of the account payments in one currency arrive in. */
export const cashCode = (currency: string): string =>
  `'invoices:cash:' || ${currency}`;

/**
 * The code of the account an invoice's payments move to: cash for a sales
 * invoice, `invoices:paid:<currency>` for a purchase bill, so what an
 * organization received counts only its customers' payments.
 */
export function invoiceCashCode(ctx: BlockSqlContext, alias: string): string {
  const currency = `${alias}.${ctx.col("invoices", "currency")}`;

  return ctx.has("invoices", "direction")
    ? `case when ${alias}.${ctx.col("invoices", "direction")} = 'purchase' then 'invoices:paid:' || ${currency} else ${cashCode(currency)} end`
    : cashCode(currency);
}

/** The ledger key of a payment with a reference, unique per organization. */
export const paymentKey = (reference: string): string =>
  `'invoice-payment:' || ${reference}`;

/** SQL fragments invoices uses to keep payments on the ledger block. */
export interface InvoiceLedger {
  /** The ledger transactions table. */
  readonly transactions: string;
  /** A ledger transaction column. */
  readonly tx: (column: string) => string;
  /** What an invoice has been paid: the negated receivable balance. */
  readonly paidTotal: (alias: string) => string;
  /** The id of an invoice's receivable account, opened when missing. */
  readonly receivable: (alias: string) => string;
  /** An invoice's payments as a JSON array, oldest first. */
  readonly payments: (alias: string) => string;
  /** Posts one payment (a negative amount is a refund) and returns its id. */
  readonly post: (
    alias: string,
    amount: string,
    paidAt: string,
    method: string,
    reference: string,
    note: string,
  ) => string;
  readonly reverse: (alias: string, payment: string, reason: string) => string;
  /** Sum of payments in one currency an organization received in a window. */
  readonly received: (
    tenant: string,
    currency: string,
    window: (column: string) => string,
  ) => string;
}

/**
 * Invoice payments on the ledger block: each invoice has a receivable account
 * (`invoice:<id>`) and each currency a cash account (`invoices:cash:<code>`). A
 * payment moves the amount from the receivable to cash; the payment id is the
 * ledger transaction id.
 */
export function invoiceLedger(ctx: BlockSqlContext): InvoiceLedger {
  const ledger = ctx.of("ledger");
  const accounts = ledger.table("accounts");
  const transactions = ledger.table("transactions");
  const entries = ledger.table("entries");
  const la = (column: string): string => ledger.col("accounts", column);
  const tx = (column: string): string => ledger.col("transactions", column);
  const le = (column: string): string => ledger.col("entries", column);
  const i = (column: string): string => ctx.col("invoices", column);
  const read = ctx.permission("read", moduleOperations("invoices").read);

  const receivableOf = (alias: string): string =>
    `(select a.${la("id")} from ${accounts} a where a.${la("tenant")} = ${alias}.${i("tenant")} and a.${la("code")} = ${receivableCode(`${alias}.${i("id")}`)})`;

  const accountFor = (alias: string, code: string, name: string): string =>
    `${ledger.fn("ledger_account_for")}(${alias}.${i("tenant")}, ${code === "cash" ? "'cash'" : "'receivable'"},
      ${code === "cash" ? invoiceCashCode(ctx, alias) : receivableCode(`${alias}.${i("id")}`)}, ${name},
      ${alias}.${i("currency")}::text, 0::smallint, ${code === "cash" ? "null, null" : `'invoices', ${alias}.${i("id")}::text`},
      null, true, ${read}, 'invoices', null)`;

  return {
    transactions,
    tx,
    paidTotal: (alias) =>
      `coalesce(-(select sum(e.${le("amount")}) from ${entries} e where e.${le("account")} = ${receivableOf(alias)}), 0)`,
    receivable: (alias) =>
      accountFor(
        alias,
        "receivable",
        `'Receivable ' || coalesce(${alias}.${i("identifier")}, ${alias}.${i("id")}::text)`,
      ),
    payments: (alias) =>
      `coalesce((select jsonb_agg(jsonb_build_object('id', y.${tx("id")}, 'amount', (-e.${le("amount")})::text, 'paidAt', y.${tx("effectiveAt")}, 'method', y.${tx("metadata")} ->> 'method', 'reference', y.${tx("metadata")} ->> 'reference', 'note', y.${tx("metadata")} ->> 'note', 'recordedBy', y.${tx("actor")}) order by y.${tx("effectiveAt")}, y.${tx("createdAt")})
        from ${entries} e join ${transactions} y on y.${tx("id")} = e.${le("transaction")}
        where e.${le("account")} = ${receivableOf(alias)}), '[]'::jsonb)`,
    post: (alias, amount, paidAt, method, reference, note) =>
      `${ledger.fn("ledger_post")}(${alias}.${i("tenant")}, case when ${amount} < 0 then 'invoice.refund' else 'invoice.payment' end,
    jsonb_build_array(
      jsonb_build_object('account', ${accountFor(alias, "receivable", `'Receivable ' || coalesce(${alias}.${i("identifier")}, ${alias}.${i("id")}::text)`)}, 'amount', -${amount}),
      jsonb_build_object('account', ${accountFor(alias, "cash", `'Invoice payments ' || ${alias}.${i("currency")}`)}, 'amount', ${amount})),
    'invoices', ${alias}.${i("id")}::text, null,
    case when ${reference} is not null then ${paymentKey(reference)} end, ${paidAt},
    jsonb_strip_nulls(jsonb_build_object('invoiceId', ${alias}.${i("id")}, 'method', ${method}, 'reference', ${reference}, 'note', ${note})))`,
    reverse: (alias, payment, reason) =>
      `${ledger.fn("ledger_post")}(${alias}.${i("tenant")}, 'invoice.payment_reversal',
    (select jsonb_agg(jsonb_build_object('account', e.${le("account")}, 'amount', (-e.${le("amount")})::text) order by e.${le("createdAt")}, e.${le("id")})
      from ${entries} e where e.${le("transaction")} = ${payment}),
    'invoices', ${alias}.${i("id")}::text, null, null, null,
    (select y.${tx("metadata")} from ${transactions} y where y.${tx("id")} = ${payment}) || jsonb_strip_nulls(jsonb_build_object('reversal', true, 'reason', ${reason})),
    ${payment})`,
    received: (tenant, currency, window) =>
      `(select coalesce(sum(e.${le("amount")}), 0) from ${entries} e
      join ${accounts} a on a.${la("id")} = e.${le("account")}
      join ${transactions} y on y.${tx("id")} = e.${le("transaction")}
      where a.${la("tenant")} = ${tenant} and a.${la("managedBy")} = 'invoices' and a.${la("code")} = ${cashCode(currency)} and ${window(`y.${tx("effectiveAt")}`)})`,
  };
}

/**
 * Moves the rows of `invoice_payments` (invoices version 1) onto the ledger,
 * keeping each payment's id as its transaction id, then drops the table.
 */
export function invoicePaymentsUpgrade(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const ledger = ctx.of("ledger");
  const accounts = ledger.table("accounts");
  const la = (column: string): string => ledger.col("accounts", column);
  const tx = (column: string): string => ledger.col("transactions", column);
  const le = (column: string): string => ledger.col("entries", column);
  const read = ctx.permission("read", moduleOperations("invoices").read);
  const invoices = ctx.table("invoices");
  const i = (column: string): string => ctx.col("invoices", column);
  const old = `${ctx.schema}.invoice_payments`;
  // The old table took the tenant column the block names on its other tables.
  const mt = ctx.col("invoices", "tenant");
  const columns = `${la("tenant")}, ${la("kind")}, ${la("code")}, ${la("name")}, ${la("unit")}, ${la("scale")}, ${la("holderType")}, ${la("holderId")}, ${la("allowNegative")}, ${la("readPermission")}, ${la("managedBy")}`;

  return `${ledgerTables(ledger)}
do $upgrade$
begin
  if to_regclass('${ctx.schemaName}.invoice_payments') is null then
    return;
  end if;
  insert into ${accounts} (${columns})
  select distinct v.${i("tenant")}, 'receivable', ${receivableCode(`v.${i("id")}`)}, 'Receivable ' || coalesce(v.${i("identifier")}, v.${i("id")}::text), v.${i("currency")}::text, 0, 'invoices', v.${i("id")}::text, true, ${read}, 'invoices'
  from ${old} m join ${invoices} v on v.${i("id")} = m.invoice_id
  on conflict do nothing;
  insert into ${accounts} (${columns})
  select distinct v.${i("tenant")}, 'cash', ${cashCode(`v.${i("currency")}`)}, 'Invoice payments ' || v.${i("currency")}, v.${i("currency")}::text, 0, null, null, true, ${read}, 'invoices'
  from ${old} m join ${invoices} v on v.${i("id")} = m.invoice_id
  on conflict do nothing;
  insert into ${ledger.table("transactions")} (${tx("id")}, ${tx("tenant")}, ${tx("kind")}, ${tx("referenceType")}, ${tx("referenceId")}, ${tx("key")}, ${tx("metadata")}, ${tx("effectiveAt")}, ${tx("actor")}, ${tx("createdAt")})
  select m.id, m.${mt}, case when m.amount < 0 then 'invoice.refund' else 'invoice.payment' end, 'invoices', m.invoice_id::text,
    case when m.reference is not null then ${paymentKey("m.reference")} end,
    jsonb_strip_nulls(jsonb_build_object('invoiceId', m.invoice_id, 'method', m.method, 'reference', m.reference)), m.paid_at, m.recorded_by, m.created_at
  from ${old} m
  on conflict do nothing;
  insert into ${ledger.table("entries")} (${le("tenant")}, ${le("transaction")}, ${le("account")}, ${le("amount")}, ${le("unit")}, ${le("createdAt")})
  select m.${mt}, m.id, x.${la("id")}, -m.amount, x.${la("unit")}, m.created_at
  from ${old} m join ${accounts} x on x.${la("tenant")} = m.${mt} and x.${la("code")} = ${receivableCode("m.invoice_id")}
  union all
  select m.${mt}, m.id, x.${la("id")}, m.amount, x.${la("unit")}, m.created_at
  from ${old} m join ${invoices} v on v.${i("id")} = m.invoice_id
  join ${accounts} x on x.${la("tenant")} = m.${mt} and x.${la("code")} = ${cashCode(`v.${i("currency")}`)};
  ${ledgerRebalance(ledger)}
  drop table ${old};
end;
$upgrade$;`;
}
