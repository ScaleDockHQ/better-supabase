import { sqlIdent } from "../../core/template.ts";
import type { BlockSqlContext, BlockSqlTableSpec } from "../context.ts";

import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { fail, serviceGrant, userGrant } from "../shared.ts";
import { lockModuleTable } from "./over-app.ts";

/** The maintained open-item row, one per invoice that still has a balance. */
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
}

/** The stored row's balance: what the invoice still owes today. */
function balanceOf(store: OpenItemStore, alias: string): string {
  const i = store.i;

  return `(${alias}.${i("total")} + ${store.charged(alias)} - ${alias}.${i("creditedTotal")} - ${alias}.${i("paidTotal")})`;
}

/**
 * The open-item table, the trigger that keeps one invoice current, and
 * `rebuild_open_items` for the end of an import.
 */
export function openItemsStoreSql(
  ctx: BlockSqlContext,
  store: OpenItemStore,
): string {
  if (!ctx.hasTable("openItems")) {
    return "";
  }

  const table = ctx.table("openItems");
  const refreshTrigger = sqlIdent(`bsb_${ctx.tableName("openItems").name}_refresh`);
  const o = (column: string): string => ctx.col("openItems", column);
  const i = store.i;
  const balance = balanceOf(store, "x");

  return `
create table if not exists ${table} (
  ${o("tenant")} ${ctx.idType} not null,
  ${o("party")} text,
  ${o("side")} text not null check (${o("side")} in ('customer', 'supplier')),
  ${o("documentType")} text not null default 'invoice',
  ${o("document")} uuid not null references ${store.invoices} (${i("id")}) on delete cascade,
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

create or replace function ${store.fn("refresh_open_item")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_balance bigint;
begin
  v_balance := ${balanceOf(store, "new")};
  delete from ${table} x
  where x.${o("document")} = new.${i("id")} and x.${o("documentType")} = 'invoice';
  if new.${i("status")}::text in ('issued', 'partially_paid', 'paid') and v_balance <> 0 and new.${i("issuedOn")} <= current_date then
    insert into ${table} (${o("tenant")}, ${o("party")}, ${o("side")}, ${o("documentType")}, ${o("document")}, ${o("currency")}, ${o("dueOn")}, ${o("issuedOn")}, ${o("gross")}, ${o("balance")})
    values (new.${i("tenant")}, ${store.partyOf("new")}, ${store.sideOf("new")}, 'invoice', new.${i("id")}, new.${i("currency")}::text,
      new.${i("dueOn")}, new.${i("issuedOn")}, (new.${i("total")} + ${store.charged("new")} - new.${i("creditedTotal")})::bigint, v_balance);
  end if;
  return null;
end;
$$;

drop trigger if exists invoice_open_items_refresh on ${store.invoices};
drop trigger if exists ${refreshTrigger} on ${store.invoices};
create trigger ${refreshTrigger}
after insert or update of ${i("status")}, ${i("paidTotal")}, ${i("total")}, ${i("creditedTotal")}, ${i("dueOn")}, ${i("issuedOn")}
on ${store.invoices}
for each row execute function ${store.fn("refresh_open_item")}();

-- Rebuilds today's open items for one organization. An import calls it once
-- after the documents are in, instead of once per row.
create or replace function ${store.fn("rebuild_open_items")}(tenant ${ctx.idType})
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if (select auth.role()) is distinct from 'service_role' and not ${ctx.scope.can("rebuild_open_items.tenant", store.read)} then
    ${fail("INVOICE_FORBIDDEN", "not allowed to read this organization's invoices", "42501")}
  end if;
  delete from ${table} x where x.${o("tenant")} = rebuild_open_items.tenant and x.${o("documentType")} = 'invoice';
  insert into ${table} (${o("tenant")}, ${o("party")}, ${o("side")}, ${o("documentType")}, ${o("document")}, ${o("currency")}, ${o("dueOn")}, ${o("issuedOn")}, ${o("gross")}, ${o("balance")})
  select x.${i("tenant")}, ${store.partyOf("x")}, ${store.sideOf("x")}, 'invoice', x.${i("id")}, x.${i("currency")}::text,
    x.${i("dueOn")}, x.${i("issuedOn")}, (x.${i("total")} + ${store.charged("x")} - x.${i("creditedTotal")})::bigint, ${balance}::bigint
  from ${store.invoices} x
  where x.${i("tenant")} = rebuild_open_items.tenant
    and ${store.invoiceKind("x")}
    and x.${i("status")}::text in ('issued', 'partially_paid', 'paid')
    and x.${i("issuedOn")} <= current_date
    and ${balance} <> 0;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
${serviceGrant(`${store.fn("rebuild_open_items")}(${ctx.idType})`)}
${userGrant(`${store.fn("rebuild_open_items")}(${ctx.idType})`)}

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
  if (select auth.role()) is distinct from 'service_role' and not ${ctx.scope.can("open_items_page.tenant", store.read)} then
    ${fail("INVOICE_FORBIDDEN", "not allowed to read this organization's invoices", "42501")}
  end if;
  select count(*) into v_total from ${table} e
  where e.${o("tenant")} = open_items_page.tenant
    and e.${o("balance")} <> 0
    and (open_items_page.party_id is null or e.${o("party")} = open_items_page.party_id)
    and (open_items_page.side is null or e.${o("side")} = open_items_page.side);
  select coalesce(jsonb_agg(row_to_json(p)), '[]'::jsonb) into v_rows from (
    select e.${o("side")} as side, e.${o("party")} as "partyId", e.${o("documentType")} as "documentType",
      e.${o("document")} as "documentId", e.${o("currency")} as currency, e.${o("dueOn")} as "dueOn",
      e.${o("issuedOn")} as "issuedOn", e.${o("gross")}::text as amount, e.${o("balance")}::text as balance
    from ${table} e
    where e.${o("tenant")} = open_items_page.tenant
      and e.${o("balance")} <> 0
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
 * Today's open invoices from the maintained table, plus unallocated payments.
 * `unallocated` is a select of `(item jsonb, ord_side, ord_party, ord_due,
 * ord_document)`.
 */
export function storedOpenItemsSql(
  ctx: BlockSqlContext,
  unallocated: string,
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

  return `
  if v_as_of = current_date then
    return coalesce((
      select jsonb_agg(s.item order by s.ord_side, s.ord_party, s.ord_due nulls last, s.ord_document)
      from (
        select jsonb_build_object(
            'side', e.${o("side")}, 'partyId', e.${o("party")}, 'documentType', e.${o("documentType")}, 'documentId', e.${o("document")},
            'currency', e.${o("currency")}, 'issuedOn', e.${o("issuedOn")}, 'dueOn', e.${o("dueOn")},
            'amount', e.${o("gross")}::text, 'balance', e.${o("balance")}::text,
            'daysOverdue', case when e.${o("dueOn")} is null then 0 else v_as_of - e.${o("dueOn")} end,
            'bucket', case when e.${o("dueOn")} is null or v_as_of - e.${o("dueOn")} <= 0 then 'current'
              when v_as_of - e.${o("dueOn")} <= 30 then 'days1To30' when v_as_of - e.${o("dueOn")} <= 60 then 'days31To60'
              when v_as_of - e.${o("dueOn")} <= 90 then 'days61To90' else 'over90' end)
            || coalesce(${invoice.fields("x")}, '{}'::jsonb) as item,
          e.${o("side")} as ord_side, e.${o("party")} as ord_party, e.${o("dueOn")} as ord_due, e.${o("document")} as ord_document
        from ${table} e
        left join ${invoice.table} x on e.${o("documentType")} = 'invoice' and x.${invoice.id} = e.${o("document")}
        where e.${o("tenant")} = open_items_for_party.tenant
          and e.${o("balance")} <> 0
          and (open_items_for_party.party_id is null or e.${o("party")} = open_items_for_party.party_id)
          and (open_items_for_party.side is null or e.${o("side")} = open_items_for_party.side)
        union all
        ${unallocated}
      ) s
    ), '[]'::jsonb);
  end if;`;
}
