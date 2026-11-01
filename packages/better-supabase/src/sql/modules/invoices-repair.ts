import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";
import type { CollectionHelpers } from "./invoices-collections.ts";
import type { InvoiceNames } from "./invoices-names.ts";

import { sqlString } from "../../core/template.ts";
import { booksAccounting } from "../accounting-sources-sql.ts";
import { documentTotals } from "../line-items-sql.ts";
import { fail, userGrant } from "../shared.ts";
import { linked } from "./banking-sql.ts";

/** The header totals the repair compares, as logical column names. */
const TOTALS = [
  "listTotal",
  "discountTotal",
  "subtotal",
  "taxTotal",
  "total",
] as const;

/** Whether this invoices table counts its totals from its lines. */
function repairs(ctx: BlockSqlContext): boolean {
  return (
    ctx.text("totals", "block") !== "app" &&
    ctx.has("invoices", "total") &&
    documentTotals(ctx, {
      lines: "lines",
      parent: "invoices",
      parentHas: (column) => ctx.has("invoices", column),
    })
  );
}

/** The contract of the repair function. */
export function repairContract(
  ctx: BlockSqlContext,
): readonly BlockSqlContractFunction[] {
  return repairs(ctx)
    ? [
        {
          name: "recompute_invoice_totals",
          args: ["{id}", "uuid[]", "boolean"],
          returns: "jsonb",
        },
      ]
    : [];
}

/**
 * `recompute_invoice_totals`: the repair for invoices that were issued before
 * the totals followed the credit restriction. It runs the recount of each
 * issued invoice, reports the stored and the recounted totals, and writes the
 * header totals and the tax lines only when `dry_run` is false. A dry run does
 * the same work in a subtransaction that it rolls back, so its report is what
 * the apply run writes.
 */
export function invoiceRepairSql(
  ctx: BlockSqlContext,
  n: InvoiceNames,
  h: CollectionHelpers,
): string {
  if (!repairs(ctx)) {
    return "";
  }

  const { fn, t } = n;
  const { i } = h;
  const columns = TOTALS.filter((column) => ctx.has("invoices", column));

  const totalsJson = (alias: string): string =>
    `jsonb_build_object(${columns.map((column) => `'${column}', ${alias}.${i(column)}::text`).join(", ")})`;

  const books = booksAccounting(ctx);
  const tax = linked(ctx, "tax");

  const ledger = books
    ? `
    select e.${ctx.of("accounting").col("entries", "id")}, e.${ctx.of("accounting").col("entries", "number")}, p.${ctx.of("accounting").col("periods", "status")}
      into v_entry, v_entry_number, v_period
    from ${ctx.of("accounting").table("entries")} e
    left join ${ctx.of("accounting").table("periods")} p on p.${ctx.of("accounting").col("periods", "id")} = e.${ctx.of("accounting").col("entries", "period")}
    where e.${ctx.of("accounting").col("entries", "tenant")} = v_row.${i("tenant")}
      and e.${ctx.of("accounting").col("entries", "sourceType")} = 'invoice'
      and e.${ctx.of("accounting").col("entries", "sourceId")} = v_row.${i("id")}::text
      and e.${ctx.of("accounting").col("entries", "status")} = 'posted';`
    : "";

  const payloadSql = `jsonb_build_object('organizationId', v_row.${i("tenant")}, 'invoiceId', v_row.${i("id")}, 'subjectType', 'invoice',
      'subjectId', v_row.${i("id")}::text, 'identifier', v_row.${i("identifier")}, 'currency', v_row.${i("currency")},
      'oldTotal', v_old ->> 'total', 'newTotal', v_new ->> 'total', 'oldTaxTotal', v_old ->> 'taxTotal',
      'newTaxTotal', v_new ->> 'taxTotal', 'needsCorrectingEntry', v_entry is not null)`;

  const events = ctx.flag("correctionEvents", false)
    ? ctx.emit({
        type: "invoice.totals_corrected",
        payload: payloadSql,
        subject: `'invoices/' || v_row.${i("id")}::text`,
        tenant: `v_row.${i("tenant")}::text`,
      })
    : "";

  const audit = ctx.audit({
    type: "invoice.totals_corrected",
    payload: payloadSql,
    subject: `'invoices/' || v_row.${i("id")}::text`,
    tenant: `v_row.${i("tenant")}::text`,
    audit: {
      category: "billing",
      targetType: "invoice",
      recordId: `v_row.${i("id")}::text`,
      targetLabel: `v_row.${i("identifier")}`,
      summary: sqlString("invoice totals corrected (system correction)"),
      metadata: "v_detail",
    },
  });

  const taxStep = tax
    ? `\n      perform ${tax.fn("issue_invoice_tax")}(v_row.${i("id")}, v_row.${i("issuedOn")});`
    : "";

  return `
-- Recounts the totals of issued invoices (not drafts or voided ones) with the
-- credit restriction of their payment terms, for invoices issued before the
-- totals followed it. invoice_ids null means every issued invoice of the
-- organization. dry_run (the default) writes nothing. An invoice whose stored
-- totals already match is left alone, so a second run changes nothing. It
-- never changes a number, an issue date or a status. The result lists the
-- invoices that differ with their old and new totals and balance, and says
-- whether a posted accounting entry books the old amounts: the entry is not
-- touched, and it needs a correcting entry. Each corrected invoice gets an
-- audit entry as a system correction; options.correctionEvents also sends an
-- event. Needs invoices.manage.
create or replace function ${fn("recompute_invoice_totals")}(tenant ${ctx.idType}, invoice_ids uuid[] default null, dry_run boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("invoices")};
  v_old jsonb;
  v_new jsonb;
  v_balance bigint;
  v_balance_after bigint;
  v_entry uuid;
  v_entry_number text;
  v_period text;
  v_detail jsonb;
  v_ledger jsonb;
  v_items jsonb := '[]'::jsonb;
  v_checked integer := 0;
  v_changed integer := 0;
begin
  if not (${n.service} or ${ctx.scope.can("recompute_invoice_totals.tenant", n.manage)}) then
    ${fail("INVOICE_FORBIDDEN", "not allowed to manage invoices in this organization", "42501")}
  end if;
  for v_row in
    select * from ${t("invoices")} x
    where x.${i("tenant")} = recompute_invoice_totals.tenant
      and ${h.st(`x.${i("status")}`, ["draft", "void"], true)}
      and (recompute_invoice_totals.invoice_ids is null or x.${i("id")} = any (recompute_invoice_totals.invoice_ids))
    order by x.${i("createdAt")}, x.${i("id")}
    for update
  loop
    v_checked := v_checked + 1;
    v_old := ${totalsJson("v_row")};
    v_balance := ${h.balance("v_row")};
    begin${taxStep}
      perform ${fn("set_invoice_lines_recount")}(v_row.${i("id")});
      select ${totalsJson("x")}, ${h.balance("x")} into v_new, v_balance_after
      from ${t("invoices")} x where x.${i("id")} = v_row.${i("id")};
      if v_new = v_old then
        raise exception using errcode = 'P0BSB', message = 'unchanged';
      end if;
      if recompute_invoice_totals.dry_run then
        raise exception using errcode = 'P0BSB', message = 'dry run';
      end if;
    exception
      when sqlstate 'P0BSB' then
        null;
    end;
    if v_new = v_old then
      continue;
    end if;
    v_changed := v_changed + 1;
    v_entry := null;
    v_entry_number := null;
    v_period := null;${ledger}
    v_ledger := jsonb_build_object('posted', v_entry is not null, 'entryId', v_entry, 'entryNumber', v_entry_number,
      'periodStatus', v_period, 'needsCorrectingEntry', v_entry is not null);
    v_detail := jsonb_build_object('correction', 'credit_restriction', 'old', v_old, 'new', v_new, 'ledger', v_ledger);
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'invoiceId', v_row.${i("id")}, 'identifier', v_row.${i("identifier")}, 'currency', v_row.${i("currency")}, 'status', v_row.${i("status")},
      'old', v_old, 'new', v_new, 'balance', v_balance::text, 'balanceAfter', v_balance_after::text,
      'ledger', v_ledger));
    if not recompute_invoice_totals.dry_run then
      ${audit}
      ${events}
    end if;
  end loop;
  return jsonb_build_object('dryRun', recompute_invoice_totals.dry_run, 'checked', v_checked, 'changed', v_changed,
    'applied', case when recompute_invoice_totals.dry_run then 0 else v_changed end, 'invoices', v_items);
end;
$$;
${userGrant(`${fn("recompute_invoice_totals")}(${ctx.idType}, uuid[], boolean)`)}
`;
}
