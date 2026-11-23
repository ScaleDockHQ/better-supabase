import type { BlockSqlContext, BlockSqlTableSpec } from "../context.ts";

import { sqlIdent } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { fail, SERVICE_CALLER, serviceGrant, userGrant } from "../shared.ts";
import { lockModuleTable } from "./over-app.ts";

/**
 * The maintained open-item row: one per invoice that still has a balance, and
 * one per party credit account that holds an unallocated payment.
 */
export const OPEN_ITEMS_TABLE: BlockSqlTableSpec = {
  name: "invoice_open_items",
  app: {},
  optionalTable: true,
  lifecycle: { tenant: "tenant", export: true },
  columns: {
    tenant: "tenant_id",
    party: "party_id",
    side: "side",
    documentType: "document_type",
    document: "document_id",
    currency: "currency",
    dueOn: "due_on",
    issuedOn: "issued_on",
    gross: "gross",
    balance: "balance",
  },
};

/** The ledger tables a party's unallocated payments are read from. */
export interface OpenItemCredit {
  readonly accounts: string;
  readonly balances: string;
  readonly entries: string;
  readonly transactions: string;
  readonly la: (column: string) => string;
  readonly lb: (column: string) => string;
  readonly le: (column: string) => string;
  readonly tx: (column: string) => string;
}

export interface OpenItemStore {
  readonly invoices: string;
  readonly read: string;
  readonly fn: (name: string) => string;
  readonly i: (column: string) => string;
  readonly charged: (alias: string) => string;
  readonly sideOf: (alias: string) => string;
  readonly partyOf: (alias: string) => string;
  readonly invoiceKind: (alias: string) => string;
  readonly openStatus: (alias: string) => string;
  /** Invoice columns besides the amounts that a stored row depends on. */
  readonly watched: readonly string[];
  readonly charges?: { readonly table: string; readonly invoice: string };
  readonly credit: OpenItemCredit;
}

/** The stored row's balance: what the invoice still owes today. */
function balanceOf(store: OpenItemStore, alias: string): string {
  const i = store.i;

  return `(${alias}.${i("total")} + ${store.charged(alias)} - ${alias}.${i("creditedTotal")} - ${alias}.${i("paidTotal")})`;
}

/** The columns of a stored row, in insert order. */
function rowColumns(ctx: BlockSqlContext): string {
  const o = (column: string): string => ctx.col("openItems", column);

  return [
    "tenant",
    "party",
    "side",
    "documentType",
    "document",
    "currency",
    "dueOn",
    "issuedOn",
    "gross",
    "balance",
  ]
    .map(o)
    .join(", ");
}

/**
 * The open invoices in the row shape, filtered by `where` on alias `x`. Issue
 * dates in the future are kept: the read filters on `issued_on`.
 */
function invoiceRows(store: OpenItemStore, where: string): string {
  const i = store.i;
  const balance = balanceOf(store, "x");

  return `select x.${i("tenant")}, ${store.partyOf("x")}, ${store.sideOf("x")}, 'invoice', x.${i("id")}, x.${i("currency")}::text,
    x.${i("dueOn")}, x.${i("issuedOn")}, (x.${i("total")} + ${store.charged("x")} - x.${i("creditedTotal")})::bigint, ${balance}::bigint
  from ${store.invoices} x
  where ${where}
    and ${store.invoiceKind("x")}
    and ${store.openStatus("x")}
    and x.${i("issuedOn")} is not null
    and ${balance} <> 0`;
}

/**
 * The unallocated payments in the row shape, filtered by `where` on alias `a`:
 * a party credit account whose kept balance is below zero.
 */
function creditRows(credit: OpenItemCredit, where: string): string {
  const { la, lb } = credit;

  return `select a.${la("tenant")}, a.${la("holderId")}, 'customer', 'unallocated_payment', a.${la("id")}, a.${la("unit")}::text,
    null::date, null::date, b.${lb("balance")}::bigint, b.${lb("balance")}::bigint
  from ${credit.accounts} a
  join ${credit.balances} b on b.${lb("account")} = a.${la("id")}
  where ${where}
    and a.${la("managedBy")} = 'invoices'
    and a.${la("holderType")} = 'invoice_party'
    and b.${lb("balance")} < 0`;
}

/**
 * The open items the fold computes for today, from ledger entries rather than
 * the kept balances, as `(document_type, document, party, gross, balance)`.
 */
function foldRows(store: OpenItemStore): string {
  const { la, le, tx } = store.credit;
  const i = store.i;
  const balance = balanceOf(store, "x");

  return `select 'invoice'::text as document_type, x.${i("id")} as document, ${store.partyOf("x")} as party,
      (x.${i("total")} + ${store.charged("x")} - x.${i("creditedTotal")})::bigint as gross, ${balance}::bigint as balance
    from ${store.invoices} x
    where x.${i("tenant")} = v_tenant
      and ${store.invoiceKind("x")}
      and ${store.openStatus("x")}
      and x.${i("issuedOn")} is not null
      and ${balance} <> 0
    union all
    select 'unallocated_payment'::text, a.${la("id")}, a.${la("holderId")}, c.amount, c.amount
    from ${store.credit.accounts} a
    cross join lateral (
      select coalesce(sum(e.${le("amount")}), 0)::bigint as amount from ${store.credit.entries} e
      join ${store.credit.transactions} y on y.${tx("id")} = e.${le("transaction")}
      where e.${le("account")} = a.${la("id")} and (y.${tx("effectiveAt")} at time zone 'UTC')::date <= current_date
    ) c
    where a.${la("tenant")} = v_tenant and a.${la("managedBy")} = 'invoices'
      and a.${la("holderType")} = 'invoice_party' and c.amount < 0`;
}

/**
 * The triggers that keep one invoice's row and one credit account's row
 * current.
 */
function refreshSql(ctx: BlockSqlContext, store: OpenItemStore): string {
  const table = ctx.table("openItems");
  const o = (column: string): string => ctx.col("openItems", column);
  const i = store.i;
  const { credit } = store;
  const name = ctx.tableName("openItems").name;
  const refreshTrigger = sqlIdent(`bsb_${name}_refresh`);
  const chargeTrigger = sqlIdent(`bsb_${name}_charge`);
  const creditTrigger = sqlIdent(`bsb_${name}_credit`);

  const watched = [
    "status",
    "paidTotal",
    "total",
    "creditedTotal",
    "dueOn",
    "issuedOn",
    "kind",
    "currency",
    ...store.watched,
  ];

  const charges = store.charges
    ? `
create or replace function ${store.fn("refresh_open_item_charge")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    perform ${store.fn("refresh_open_item_of")}(old.${store.charges.invoice});
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    perform ${store.fn("refresh_open_item_of")}(new.${store.charges.invoice});
  end if;
  return null;
end;
$$;
revoke execute on function ${store.fn("refresh_open_item_charge")}() from public, anon, authenticated;

drop trigger if exists ${chargeTrigger} on ${store.charges.table};
create trigger ${chargeTrigger}
after insert or update or delete on ${store.charges.table}
for each row execute function ${store.fn("refresh_open_item_charge")}();
`
    : "";

  return `
-- Writes the stored row of one invoice again from the invoice as it stands.
create or replace function ${store.fn("refresh_open_item_of")}(invoice uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from ${table} e
  where e.${o("document")} = refresh_open_item_of.invoice and e.${o("documentType")} = 'invoice';
  insert into ${table} (${rowColumns(ctx)})
  ${invoiceRows(store, `x.${i("id")} = refresh_open_item_of.invoice`)};
end;
$$;
revoke execute on function ${store.fn("refresh_open_item_of")}(uuid) from public, anon, authenticated;

create or replace function ${store.fn("refresh_open_item")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    delete from ${table} e
    where e.${o("document")} = old.${i("id")} and e.${o("documentType")} = 'invoice';
    return null;
  end if;
  perform ${store.fn("refresh_open_item_of")}(new.${i("id")});
  return null;
end;
$$;
revoke execute on function ${store.fn("refresh_open_item")}() from public, anon, authenticated;

drop trigger if exists invoice_open_items_refresh on ${store.invoices};
drop trigger if exists ${refreshTrigger} on ${store.invoices};
create trigger ${refreshTrigger}
after insert or delete or update of ${watched.map(i).join(", ")}
on ${store.invoices}
for each row execute function ${store.fn("refresh_open_item")}();
${charges}
-- Keeps the unallocated row of a party credit account next to its balance.
create or replace function ${store.fn("refresh_open_credit")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from ${credit.accounts} a
    where a.${credit.la("id")} = new.${credit.lb("account")}
      and a.${credit.la("managedBy")} = 'invoices' and a.${credit.la("holderType")} = 'invoice_party'
  ) then
    return null;
  end if;
  delete from ${table} e
  where e.${o("document")} = new.${credit.lb("account")} and e.${o("documentType")} = 'unallocated_payment';
  insert into ${table} (${rowColumns(ctx)})
  ${creditRows(credit, `a.${credit.la("id")} = new.${credit.lb("account")}`)};
  return null;
end;
$$;
revoke execute on function ${store.fn("refresh_open_credit")}() from public, anon, authenticated;

drop trigger if exists ${creditTrigger} on ${credit.balances};
create trigger ${creditTrigger}
after insert or update of ${credit.lb("balance")} on ${credit.balances}
for each row execute function ${store.fn("refresh_open_credit")}();
`;
}

/** Rebuild and drift: the stored rows against what the fold computes. */
function maintenanceSql(ctx: BlockSqlContext, store: OpenItemStore): string {
  const table = ctx.table("openItems");
  const o = (column: string): string => ctx.col("openItems", column);
  const i = store.i;
  const { credit } = store;
  const tenant = ctx.idType;

  return `
-- Writes every stored row of one organization again. No permission check:
-- rebuild_open_items and the module's data migration call it.
create or replace function ${store.fn("rebuild_open_items_of")}(tenant ${tenant})
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  delete from ${table} e where e.${o("tenant")} = rebuild_open_items_of.tenant;
  insert into ${table} (${rowColumns(ctx)})
  ${invoiceRows(store, `x.${i("tenant")} = rebuild_open_items_of.tenant`)}
  union all
  ${creditRows(credit, `a.${credit.la("tenant")} = rebuild_open_items_of.tenant`)};
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function ${store.fn("rebuild_open_items_of")}(${tenant}) from public, anon, authenticated;

-- Rebuilds the open items of one organization. An import calls it once after
-- the documents are in, and doctor names it as the fix for drift.
create or replace function ${store.fn("rebuild_open_items")}(tenant ${tenant})
returns integer
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (${SERVICE_CALLER} or ${ctx.scope.can("rebuild_open_items.tenant", store.read)}) then
    ${fail("INVOICE_FORBIDDEN", "not allowed to read this organization's invoices", "42501")}
  end if;
  return ${store.fn("rebuild_open_items_of")}(rebuild_open_items.tenant);
end;
$$;
${serviceGrant(`${store.fn("rebuild_open_items")}(${tenant})`)}
${userGrant(`${store.fn("rebuild_open_items")}(${tenant})`)}

-- The stored rows that differ from the fold, at most 100. No permission
-- check: open_items_drift and import_integrity call it.
create or replace function ${store.fn("open_items_drift_rows")}(tenant ${tenant})
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant ${tenant} := open_items_drift_rows.tenant;
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
        'documentType', coalesce(s.document_type, f.document_type), 'documentId', coalesce(s.document, f.document),
        'stored', s.balance::text, 'fold', f.balance::text)
      order by coalesce(s.document_type, f.document_type), coalesce(s.document, f.document))
    from (
      select e.${o("documentType")} as document_type, e.${o("document")} as document, e.${o("party")} as party,
        e.${o("gross")} as gross, e.${o("balance")} as balance
      from ${table} e where e.${o("tenant")} = v_tenant
    ) s
    full join (${foldRows(store)}) f
      on f.document_type = s.document_type and f.document = s.document
    where s.document is null or f.document is null
      or s.balance <> f.balance or s.gross <> f.gross or s.party is distinct from f.party
    limit 100
  ), '[]'::jsonb);
end;
$$;
revoke execute on function ${store.fn("open_items_drift_rows")}(${tenant}) from public, anon, authenticated;

-- Where the stored open items of one organization differ from the fold over
-- invoices and ledger entries. An empty array means none.
create or replace function ${store.fn("open_items_drift")}(tenant ${tenant})
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (${SERVICE_CALLER} or ${ctx.scope.can("open_items_drift.tenant", store.read)}) then
    ${fail("INVOICE_FORBIDDEN", "not allowed to read this organization's invoices", "42501")}
  end if;
  return ${store.fn("open_items_drift_rows")}(open_items_drift.tenant);
end;
$$;
${serviceGrant(`${store.fn("open_items_drift")}(${tenant})`)}
${userGrant(`${store.fn("open_items_drift")}(${tenant})`)}
`;
}

/**
 * The open-item table, the triggers that keep it current, rebuild and drift,
 * and the stored page read.
 */
export function openItemsStoreSql(
  ctx: BlockSqlContext,
  store: OpenItemStore,
): string {
  if (!ctx.hasTable("openItems")) {
    return "";
  }

  const table = ctx.table("openItems");
  const o = (column: string): string => ctx.col("openItems", column);
  const shown = `(e.${o("documentType")} = 'unallocated_payment' or e.${o("issuedOn")} <= current_date)`;

  return `
create table if not exists ${table} (
  ${o("tenant")} ${ctx.idType} not null,
  ${o("party")} text,
  ${o("side")} text not null check (${o("side")} in ('customer', 'supplier')),
  ${o("documentType")} text not null default 'invoice' check (${o("documentType")} in ('invoice', 'unallocated_payment')),
  ${o("document")} uuid not null,
  ${o("currency")} text not null,
  ${o("dueOn")} date,
  ${o("issuedOn")} date,
  ${o("gross")} bigint not null,
  ${o("balance")} bigint not null,
  primary key (${o("tenant")}, ${o("documentType")}, ${o("document")})
);
create index if not exists ${ctx.naming.rename("invoice_open_items_document_idx")} on ${table} (${o("document")});
create index if not exists ${ctx.naming.rename("invoice_open_items_party_idx")} on ${table} (${o("tenant")}, ${o("party")}, ${o("side")});
create index if not exists ${ctx.naming.rename("invoice_open_items_due_idx")} on ${table} (${o("tenant")}, ${o("dueOn")});
${lockModuleTable(ctx, "openItems", { read: true })}
${renderPolicy(
  makePolicy({
    table,
    name: ctx.naming.rename("invoice_open_items_read"),
    command: "select",
    roles: ["authenticated"],
    using: ctx.scope.check(o("tenant"), store.read),
  }),
  { target: table },
)}
${refreshSql(ctx, store)}
${maintenanceSql(ctx, store)}
-- One page of today's open items, with a total that stops at count_cap.
create or replace function ${store.fn("open_items_page")}(
  tenant ${ctx.idType},
  side text default null,
  party_id text default null,
  "limit" integer default 50,
  "offset" integer default 0,
  count_cap integer default 10000
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_total integer;
  v_rows jsonb;
begin
  if not (${SERVICE_CALLER} or ${ctx.scope.can("open_items_page.tenant", store.read)}) then
    ${fail("INVOICE_FORBIDDEN", "not allowed to read this organization's invoices", "42501")}
  end if;
  select count(*) into v_total from ${table} e
  where e.${o("tenant")} = open_items_page.tenant
    and e.${o("balance")} <> 0
    and ${shown}
    and (open_items_page.party_id is null or e.${o("party")} = open_items_page.party_id)
    and (open_items_page.side is null or e.${o("side")} = open_items_page.side);
  select coalesce(jsonb_agg(row_to_json(p)), '[]'::jsonb) into v_rows from (
    select e.${o("side")} as side, e.${o("party")} as "partyId", e.${o("documentType")} as "documentType",
      e.${o("document")} as "documentId", e.${o("currency")} as currency, e.${o("dueOn")} as "dueOn",
      e.${o("issuedOn")} as "issuedOn", e.${o("gross")}::text as amount, e.${o("balance")}::text as balance
    from ${table} e
    where e.${o("tenant")} = open_items_page.tenant
      and e.${o("balance")} <> 0
      and ${shown}
      and (open_items_page.party_id is null or e.${o("party")} = open_items_page.party_id)
      and (open_items_page.side is null or e.${o("side")} = open_items_page.side)
    order by e.${o("dueOn")} nulls last, e.${o("document")}
    limit least(greatest(coalesce(open_items_page."limit", 50), 1), 200)
    offset greatest(coalesce(open_items_page."offset", 0), 0)
  ) p;
  return jsonb_build_object('rows', v_rows, 'total', least(v_total, coalesce(open_items_page.count_cap, 10000)));
end;
$$;
${serviceGrant(`${store.fn("open_items_page")}(${ctx.idType}, text, text, integer, integer, integer)`)}
${userGrant(`${store.fn("open_items_page")}(${ctx.idType}, text, text, integer, integer, integer)`)}
`;
}

/**
 * Today's open items from the maintained table: invoices issued by today and
 * unallocated payments. A past `as_of` falls through to the fold.
 */
export function storedOpenItemsSql(
  ctx: BlockSqlContext,
  invoice: {
    readonly table: string;
    readonly id: string;
    readonly fields: (alias: string) => string;
  },
): string {
  if (!ctx.hasTable("openItems")) {
    return "";
  }

  const table = ctx.table("openItems");
  const o = (column: string): string => ctx.col("openItems", column);
  const days = `case when e.${o("dueOn")} is null then 0 else v_as_of - e.${o("dueOn")} end`;

  return `
  if v_as_of = current_date then
    return coalesce((
      select jsonb_agg(s.item order by s.ord_side, s.ord_party, s.ord_due nulls last, s.ord_document)
      from (
        select jsonb_build_object(
            'side', e.${o("side")}, 'partyId', e.${o("party")}, 'documentType', e.${o("documentType")}, 'documentId', e.${o("document")},
            'currency', e.${o("currency")}, 'issuedOn', e.${o("issuedOn")}, 'dueOn', e.${o("dueOn")},
            'amount', e.${o("gross")}::text, 'balance', e.${o("balance")}::text,
            'daysOverdue', ${days},
            'bucket', case when e.${o("documentType")} = 'unallocated_payment' then 'unallocated'
              when ${days} <= 0 then 'current'
              when ${days} <= 30 then 'days1To30' when ${days} <= 60 then 'days31To60'
              when ${days} <= 90 then 'days61To90' else 'over90' end)
            || coalesce(${invoice.fields("x")}, '{}'::jsonb) as item,
          e.${o("side")} as ord_side, e.${o("party")} as ord_party, e.${o("dueOn")} as ord_due, e.${o("document")} as ord_document
        from ${table} e
        left join ${invoice.table} x on e.${o("documentType")} = 'invoice' and x.${invoice.id} = e.${o("document")}
        where e.${o("tenant")} = open_items_for_party.tenant
          and e.${o("balance")} <> 0
          and (e.${o("documentType")} = 'unallocated_payment' or e.${o("issuedOn")} <= v_as_of)
          and (open_items_for_party.party_id is null or e.${o("party")} = open_items_for_party.party_id)
          and (open_items_for_party.side is null or e.${o("side")} = open_items_for_party.side)
      ) s
    ), '[]'::jsonb);
  end if;`;
}

/**
 * The data migration line that rebuilds the stored rows of every organization
 * with invoices or party credit.
 */
export function rebuildOpenItemsData(ctx: BlockSqlContext): string {
  if (!ctx.hasTable("openItems")) {
    return "";
  }

  const ledger = ctx.of("ledger");
  const la = (column: string): string => ledger.col("accounts", column);
  const i = (column: string): string => ctx.col("invoices", column);

  return `-- Open items store v4: rows for unallocated payments and future issue dates.
select ${ctx.fn("rebuild_open_items_of")}(x.tenant) from (
  select ${i("tenant")} as tenant from ${ctx.table("invoices")}
  union
  select ${la("tenant")} from ${ledger.table("accounts")} where ${la("managedBy")} = 'invoices' and ${la("holderType")} = 'invoice_party'
) x;
`;
}
