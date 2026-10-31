import type { BlockSqlContext } from "../context.ts";
import type { ImportTargetContribution } from "../contributions.ts";
import type { InvoiceNames } from "./invoices-names.ts";

import { sqlString } from "../../core/template.ts";
import { hasLegalEntityColumn } from "../numbering-sql.ts";
import { fail, serviceGrant } from "../shared.ts";
import { linked } from "./manufacturing-sql.ts";

/** An import target names its functions as `schema.function`, without quotes. */
const plain = (qualified: string): string => qualified.replaceAll('"', "");

/**
 * The import targets of invoices and credit notes (ADR 0141). One document goes
 * through the same functions a user calls (`create_invoice`, `issue_invoice`
 * with its fixed number, `credit_invoice`, `record_invoice_payment`), so every
 * check, trigger and number counter applies, while import mode keeps events and
 * accounting posts out. The stored totals and tax lines then replace what the
 * lines computed, and a difference becomes a warning on the item.
 */
export function invoiceImportFunctions(
  ctx: BlockSqlContext,
  n: InvoiceNames,
): string {
  const { fn, t } = n;
  const i = (column: string): string => n.c("invoices", column);
  const has = (logical: string): boolean => ctx.has("invoices", logical);
  const tax = linked(ctx, "tax");
  const entity = hasLegalEntityColumn(ctx, "invoices");
  const totals = !n.appTotals;

  const taxLines =
    tax === undefined
      ? ""
      : (() => {
          const q = (column: string): string =>
            tax.col("invoiceTaxLines", column);

          const table = tax.table("invoiceTaxLines");

          return `
  if jsonb_typeof(v_data -> 'taxLines') = 'array' then
    v_computed := coalesce((
      select jsonb_object_agg(k.key, jsonb_build_object('net', k.net, 'tax', k.tax))
      from (select coalesce(y.${q("taxCode")}, '') || ':' || y.${q("taxRateBps")}::text as key, sum(y.${q("net")}) as net, sum(y.${q("tax")}) as tax
        from ${table} y where y.${q("parent")} = v_id group by 1) k
    ), '{}'::jsonb);
    v_given := coalesce((
      select jsonb_object_agg(k.key, jsonb_build_object('net', k.net, 'tax', k.tax))
      from (select coalesce(g.value ->> 'taxCode', '') || ':' || coalesce((g.value ->> 'taxRateBps')::integer, 0)::text as key,
          sum((g.value ->> 'net')::bigint) as net, sum((g.value ->> 'tax')::bigint) as tax
        from jsonb_array_elements(v_data -> 'taxLines') g group by 1) k
    ), '{}'::jsonb);
    if v_computed <> v_given then
      v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_TAX_MISMATCH', 'message', 'the stored tax per code differs from the tax computed from the lines; the stored amounts were kept', 'computed', v_computed, 'given', v_given));
    end if;
    delete from ${table} y where y.${q("parent")} = v_id;
    insert into ${table} (${q("tenant")}, ${q("parent")}, ${q("taxRateBps")}, ${q("taxCode")}, ${q("taxCodeId")}, ${q("net")}, ${q("tax")}, ${q("gross")}, ${q("discount")}, ${q("showTax")})
    select v_tenant, v_id, coalesce((g.value ->> 'taxRateBps')::integer, 0), nullif(g.value ->> 'taxCode', ''), nullif(g.value ->> 'taxCodeId', '')::uuid,
      (g.value ->> 'net')::bigint, (g.value ->> 'tax')::bigint,
      coalesce((g.value ->> 'gross')::bigint, (g.value ->> 'net')::bigint + (g.value ->> 'tax')::bigint),
      coalesce((g.value ->> 'discount')::bigint, 0), coalesce((g.value ->> 'showTax')::boolean, true)
    from jsonb_array_elements(v_data -> 'taxLines') g;
  end if;`;
        })();

  const header = [
    ...(entity
      ? [
          `legal_entity_id = case when v_credit then x.legal_entity_id else nullif(v_data ->> 'legalEntityId', '')::uuid end`,
        ]
      : []),
    ...(has("buyer")
      ? [
          `${i("buyer")} = case when jsonb_typeof(v_data -> 'buyer') = 'object' then v_data -> 'buyer' else x.${i("buyer")} end`,
        ]
      : []),
    ...(has("createdAt")
      ? [
          `${i("createdAt")} = coalesce(nullif(v_data ->> 'createdAt', '')::timestamptz, x.${i("createdAt")})`,
        ]
      : []),
  ];

  const totalsSql = totals
    ? `
  if jsonb_typeof(v_data -> 'totals') = 'object' then
    select * into v_row from ${t("invoices")} x where x.${i("id")} = v_id;
    if (v_data -> 'totals' ->> 'subtotal' is not null and (v_data -> 'totals' ->> 'subtotal')::bigint <> v_row.${i("subtotal")})
      or (v_data -> 'totals' ->> 'tax' is not null and (v_data -> 'totals' ->> 'tax')::bigint <> v_row.${i("taxTotal")})
      or (v_data -> 'totals' ->> 'total' is not null and (v_data -> 'totals' ->> 'total')::bigint <> v_row.${i("total")}) then
      v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_TOTALS_MISMATCH', 'message', 'the stored totals differ from the totals computed from the lines; the stored totals were kept',
        'computed', jsonb_build_object('subtotal', v_row.${i("subtotal")}::text, 'tax', v_row.${i("taxTotal")}::text, 'total', v_row.${i("total")}::text),
        'given', v_data -> 'totals'));
    end if;
    update ${t("invoices")} x set
      ${i("subtotal")} = coalesce((v_data -> 'totals' ->> 'subtotal')::bigint, x.${i("subtotal")}),
      ${i("taxTotal")} = coalesce((v_data -> 'totals' ->> 'tax')::bigint, x.${i("taxTotal")}),
      ${i("total")} = coalesce((v_data -> 'totals' ->> 'total')::bigint, x.${i("total")})
    where x.${i("id")} = v_id;
  end if;`
    : "";

  const paidAt = has("paidAt")
    ? `
    update ${t("invoices")} x set ${i("paidAt")} = (select max((p.value ->> 'paidAt')::timestamptz) from jsonb_array_elements(v_data -> 'payments') p)
    where x.${i("id")} = v_id and x.${i("paidAt")} is not null and jsonb_typeof(v_data -> 'payments') = 'array';`
    : "";

  return `
-- The shared body of the invoice and credit_note import targets (ADR 0141).
-- item.data is { number, issuedOn, dueOn?, status?, title?, currency, termsDays?, note?,
-- company?, contact?, origin?, direction?, legalEntityId?, buyer?, createdAt?,
-- pricesIncludeTax?, attrs?, lines, taxLines?, totals?, payments? }; a credit
-- note adds originalId or original (the identifier of the credited invoice).
-- The document is created and issued with its number as is, takes the stored
-- tax and totals, then its payments with their original dates. A document that
-- is already imported is kept as it is: the item reports a warning.
create or replace function ${fn("import_invoice_document")}(item jsonb, subject_id text, v_credit boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType} := (import_invoice_document.item ->> 'tenant')::${ctx.idType};
  v_data jsonb := import_invoice_document.item -> 'data';
  v_status text := case when v_credit then 'issued' else coalesce(v_data ->> 'status', 'issued') end;
  v_number text := nullif(btrim(v_data ->> 'number'), '');
  v_issued_on date;
  v_due_on date;
  v_original uuid;
  v_made jsonb;
  v_id uuid;
  v_row ${t("invoices")};
  v_warnings jsonb := '[]'::jsonb;
  v_computed jsonb;
  v_given jsonb;
  v_pay jsonb;
  v_index integer := 0;
begin
  if import_invoice_document.subject_id is not null then
    select * into v_row from ${t("invoices")} x where x.${i("id")} = import_invoice_document.subject_id::uuid and x.${i("tenant")} = v_tenant;
    if not found then
      ${fail("IMPORT_ITEM_INVALID", "the invoice no longer exists", "22023")}
    end if;
    return jsonb_build_object('subjectId', v_row.${i("id")}::text, 'updatedAt', v_row.${i("updatedAt")}, 'warnings', jsonb_build_array(jsonb_build_object('code', 'IMPORT_DOCUMENT_CHANGED', 'message', 'the source document changed after it was imported; an imported document is kept as imported, so void or credit it and import the correction as a new document')));
  end if;
  if v_status not in ('draft', 'issued', 'partially_paid', 'paid', 'void', 'uncollectible') then
    ${fail("IMPORT_ITEM_INVALID", "status is draft, issued, partially_paid, paid, void or uncollectible", "22023")}
  end if;
  if jsonb_typeof(v_data -> 'lines') is distinct from 'array' or jsonb_array_length(v_data -> 'lines') = 0 then
    ${fail("IMPORT_ITEM_INVALID", "a document needs at least one line", "22023")}
  end if;
  if v_status <> 'draft' and v_number is null then
    ${fail("IMPORT_ITEM_INVALID", "an issued document needs its number", "22023")}
  end if;
  begin
    v_issued_on := nullif(v_data ->> 'issuedOn', '')::date;
    v_due_on := nullif(v_data ->> 'dueOn', '')::date;
  exception when others then
    ${fail("IMPORT_ITEM_INVALID", "issuedOn and dueOn are dates", "22023")}
  end;
  if v_status <> 'draft' and v_issued_on is null then
    ${fail("IMPORT_ITEM_INVALID", "an issued document needs its issue date", "22023")}
  end if;

  if v_credit then
    v_original := coalesce(
      nullif(v_data ->> 'originalId', '')::uuid,
      (select x.${i("id")} from ${t("invoices")} x where x.${i("tenant")} = v_tenant and x.${i("identifier")} = v_data ->> 'original' limit 1)
    );
    if v_original is null then
      ${fail("IMPORT_ITEM_INVALID", "a credit note names the invoice it credits (originalId or original)", "22023")}
    end if;
    v_made := ${fn("credit_invoice")}(v_original, v_data -> 'lines', nullif(v_data ->> 'note', ''), v_number, v_issued_on);
    v_id := (v_made ->> ${sqlString(plain(i("id")))})::uuid;
  else
    v_made := ${fn("create_invoice")}(v_tenant, coalesce(v_data -> 'attrs', '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
      'title', coalesce(nullif(v_data ->> 'title', ''), 'Invoice ' || coalesce(v_number, 'draft')),
      'currency', v_data -> 'currency',
      'termsDays', v_data -> 'termsDays',
      'note', v_data -> 'note',
      'company', v_data -> 'company',
      'contact', v_data -> 'contact',
      'origin', v_data -> 'origin',
      'direction', v_data -> 'direction',
      'pricesIncludeTax', v_data -> 'pricesIncludeTax',
      'discountBps', v_data -> 'discountBps',
      'discountAmount', v_data -> 'discountAmount')), v_data -> 'lines');
    v_id := (v_made ->> ${sqlString(plain(i("id")))})::uuid;
  end if;${
    header.length === 0
      ? ""
      : `
  update ${t("invoices")} x set ${header.join(",\n    ")}
  where x.${i("id")} = v_id;`
  }
  if v_status <> 'draft' and not v_credit then
    perform ${fn("issue_invoice")}(v_id, v_issued_on, v_due_on, null, v_number);
  end if;${taxLines}${totalsSql}
  if jsonb_typeof(v_data -> 'payments') = 'array' and jsonb_array_length(v_data -> 'payments') > 0 then
    if v_credit or v_status = 'draft' then
      ${fail("IMPORT_ITEM_INVALID", "only an issued invoice takes payments", "22023")}
    end if;
    select * into v_row from ${t("invoices")} x where x.${i("id")} = v_id;
    for v_pay in select p.value from jsonb_array_elements(v_data -> 'payments') p loop
      v_index := v_index + 1;
      perform ${fn("record_invoice_payment")}(
        v_id, (v_pay ->> 'amount')::bigint, upper(coalesce(v_pay ->> 'currency', v_row.${i("currency")})),
        (v_pay ->> 'paidAt')::timestamptz, coalesce(nullif(v_pay ->> 'method', ''), 'import'),
        coalesce(nullif(v_pay ->> 'reference', ''), import_invoice_document.item ->> 'key' || ':payment:' || v_index::text),
        nullif(v_pay ->> 'note', ''), null, null);
    end loop;${paidAt}
  end if;
  if v_status = 'void' then
    perform ${fn("void_invoice")}(v_id, coalesce(nullif(v_data ->> 'voidReason', ''), 'imported as void'));
  elsif v_status = 'uncollectible' then
    perform ${fn("write_off_invoice")}(v_id, nullif(v_data ->> 'writeOffReason', ''));
  end if;
  select * into v_row from ${t("invoices")} x where x.${i("id")} = v_id;
  if v_status in ('partially_paid', 'paid') and v_row.${i("status")}::text <> v_status then
    v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_STATUS_MISMATCH', 'message', 'the payments give the status ' || v_row.${i("status")}::text || ', not ' || v_status, 'status', v_row.${i("status")}::text));
  end if;
  return jsonb_build_object('subjectId', v_id::text, 'updatedAt', v_row.${i("updatedAt")}, 'warnings', v_warnings);
end;
$$;
revoke execute on function ${fn("import_invoice_document")}(jsonb, text, boolean) from public, anon, authenticated;

create or replace function ${fn("import_invoice")}(run uuid, item jsonb, subject_id text)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select ${fn("import_invoice_document")}(import_invoice.item, import_invoice.subject_id, false)
$$;
${serviceGrant(`${fn("import_invoice")}(uuid, jsonb, text)`)}

create or replace function ${fn("import_credit_note")}(run uuid, item jsonb, subject_id text)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select ${fn("import_invoice_document")}(import_credit_note.item, import_credit_note.subject_id, true)
$$;
${serviceGrant(`${fn("import_credit_note")}(uuid, jsonb, text)`)}

-- The open_item import target: an opening open-item list. item.data is
-- { number, issuedOn, dueOn?, currency, balance, side? (customer or supplier),
-- title?, company?, contact?, legalEntityId? } for one open invoice or bill; it
-- imports as an issued document of one line for the open balance with its
-- original number and dates, so ageing and allocation work on it. Importing the
-- same row again writes nothing.
create or replace function ${fn("import_open_item")}(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_data jsonb := import_open_item.item -> 'data';
  v_balance bigint;
begin
  if jsonb_typeof(v_data) is distinct from 'object' or coalesce(v_data ->> 'balance', '') !~ '^[0-9]{1,18}$' or (v_data ->> 'balance')::bigint = 0 then
    ${fail("IMPORT_ITEM_INVALID", "an open item has a positive integer balance in minor units", "22023")}
  end if;
  if coalesce(v_data ->> 'side', 'customer') not in ('customer', 'supplier') then
    ${fail("IMPORT_ITEM_INVALID", "side is customer or supplier", "22023")}
  end if;
  v_balance := (v_data ->> 'balance')::bigint;
  return ${fn("import_invoice_document")}(jsonb_set(import_open_item.item, '{data}', jsonb_strip_nulls(jsonb_build_object(
    'number', v_data -> 'number', 'status', 'issued', 'issuedOn', v_data -> 'issuedOn', 'dueOn', v_data -> 'dueOn',
    'currency', v_data -> 'currency', 'company', v_data -> 'company', 'contact', v_data -> 'contact',
    'legalEntityId', v_data -> 'legalEntityId',${
      has("direction")
        ? `
    'direction', case when v_data ->> 'side' = 'supplier' then 'purchase' else 'sales' end,`
        : ""
    }
    'title', coalesce(nullif(v_data ->> 'title', ''), 'Opening balance ' || coalesce(v_data ->> 'number', '')),
    'lines', jsonb_build_array(jsonb_build_object('description', 'Opening balance ' || coalesce(v_data ->> 'number', ''),
      'quantity', 1, 'unitAmount', v_balance, 'taxRateBps', 0)),
    'totals', jsonb_build_object('subtotal', v_balance, 'tax', 0, 'total', v_balance)))),
    import_open_item.subject_id, false);
end;
$$;
${serviceGrant(`${fn("import_open_item")}(uuid, jsonb, text)`)}

-- When an invoice last changed, for the conflict check of imports.
create or replace function ${fn("invoice_updated_at")}(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select x.${i("updatedAt")} from ${t("invoices")} x where x.${i("id")} = $1::uuid
$$;
${serviceGrant(`${fn("invoice_updated_at")}(text)`)}
`;
}

/** What `contributes.imports` returns: the invoice and credit note targets. */
export function invoiceImportTargets(
  own: BlockSqlContext,
): readonly ImportTargetContribution[] {
  return [
    {
      entity: "invoice",
      subjectType: "invoice",
      write: plain(own.fn("import_invoice")),
      updatedAt: plain(own.fn("invoice_updated_at")),
    },
    {
      entity: "credit_note",
      subjectType: "invoice",
      write: plain(own.fn("import_credit_note")),
      updatedAt: plain(own.fn("invoice_updated_at")),
    },
    {
      entity: "open_item",
      subjectType: "invoice",
      write: plain(own.fn("import_open_item")),
      updatedAt: plain(own.fn("invoice_updated_at")),
    },
  ];
}
