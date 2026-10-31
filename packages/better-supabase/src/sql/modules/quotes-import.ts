import type { BlockSqlContext } from "../context.ts";
import type { ImportTargetContribution } from "../contributions.ts";
import type { QuoteNames } from "./quotes-functions.ts";

import { sqlString } from "../../core/template.ts";
import { hasLegalEntityColumn } from "../numbering-sql.ts";
import { fail, serviceGrant } from "../shared.ts";

/** An import target names its functions as `schema.function`, without quotes. */
const plain = (qualified: string): string => qualified.replaceAll('"', "");

/**
 * The import target of the `quote` entity (ADR 0141). The quote goes through
 * `create_quote` with its number as is, then takes the status, the dates and
 * the answer it had, and the stored totals and tax per rate. No version is
 * published, no link is made and no event fires.
 */
export function quoteImportFunctions(
  ctx: BlockSqlContext,
  n: QuoteNames,
): string {
  const { fn, t } = n;
  const q = (column: string): string => n.c("quotes", column);
  const has = (logical: string): boolean => ctx.has("quotes", logical);
  const x = (column: string): string => n.c("taxLines", column);
  const taxTable = ctx.hasTable("taxLines");

  const sets = [
    `${q("status")} = ${ctx.cast("quotes", "status", "coalesce(v_data ->> 'status', 'draft')")}`,
    `${q("createdAt")} = coalesce(nullif(v_data ->> 'createdAt', '')::timestamptz, y.${q("createdAt")})`,
    `${q("sentAt")} = nullif(v_data ->> 'sentAt', '')::timestamptz`,
    ...(has("viewedAt")
      ? [`${q("viewedAt")} = nullif(v_data ->> 'viewedAt', '')::timestamptz`]
      : []),
    `${q("decidedAt")} = nullif(v_data ->> 'decidedAt', '')::timestamptz`,
    `${q("decidedBy")} = nullif(v_data ->> 'decidedBy', '')`,
    ...(has("decisionNote")
      ? [`${q("decisionNote")} = nullif(v_data ->> 'decisionNote', '')`]
      : []),
    ...(has("buyer")
      ? [
          `${q("buyer")} = case when jsonb_typeof(v_data -> 'buyer') = 'object' then v_data -> 'buyer' end`,
        ]
      : []),
    ...(hasLegalEntityColumn(ctx, "quotes")
      ? ["legal_entity_id = nullif(v_data ->> 'legalEntityId', '')::uuid"]
      : []),
    `${q("updatedAt")} = now()`,
  ];

  const totals = n.appTotals
    ? ""
    : `
  if jsonb_typeof(v_data -> 'totals') = 'object' then
    select * into v_row from ${t("quotes")} y where y.${q("id")} = v_id;
    if (v_data -> 'totals' ->> 'subtotal' is not null and (v_data -> 'totals' ->> 'subtotal')::bigint <> v_row.${q("subtotal")})
      or (v_data -> 'totals' ->> 'tax' is not null and (v_data -> 'totals' ->> 'tax')::bigint <> v_row.${q("taxTotal")})
      or (v_data -> 'totals' ->> 'total' is not null and (v_data -> 'totals' ->> 'total')::bigint <> v_row.${q("total")}) then
      v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_TOTALS_MISMATCH', 'message', 'the stored totals differ from the totals computed from the lines; the stored totals were kept',
        'computed', jsonb_build_object('subtotal', v_row.${q("subtotal")}::text, 'tax', v_row.${q("taxTotal")}::text, 'total', v_row.${q("total")}::text),
        'given', v_data -> 'totals'));
    end if;
    update ${t("quotes")} y set
      ${q("subtotal")} = coalesce((v_data -> 'totals' ->> 'subtotal')::bigint, y.${q("subtotal")}),
      ${q("taxTotal")} = coalesce((v_data -> 'totals' ->> 'tax')::bigint, y.${q("taxTotal")}),
      ${q("total")} = coalesce((v_data -> 'totals' ->> 'total')::bigint, y.${q("total")})
    where y.${q("id")} = v_id;
  end if;`;

  const taxLines = taxTable
    ? `
  if jsonb_typeof(v_data -> 'taxLines') = 'array' then
    v_computed := coalesce((
      select jsonb_object_agg(k.key, jsonb_build_object('net', k.net, 'tax', k.tax))
      from (select ${ctx.has("taxLines", "taxCode") ? `coalesce(z.${x("taxCode")}, '')` : "''"} || ':' || z.${x("taxRateBps")}::text as key, sum(z.${x("net")}) as net, sum(z.${x("tax")}) as tax
        from ${t("taxLines")} z where z.${x("parent")} = v_id group by 1) k
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
    delete from ${t("taxLines")} z where z.${x("parent")} = v_id;
    insert into ${t("taxLines")} (${x("tenant")}, ${x("parent")}, ${x("taxRateBps")}${ctx.has("taxLines", "taxCode") ? `, ${x("taxCode")}` : ""}, ${x("net")}, ${x("tax")}, ${x("gross")}${ctx.has("taxLines", "discount") ? `, ${x("discount")}` : ""})
    select v_tenant, v_id, coalesce((g.value ->> 'taxRateBps')::integer, 0)${ctx.has("taxLines", "taxCode") ? ", nullif(g.value ->> 'taxCode', '')" : ""}, (g.value ->> 'net')::bigint, (g.value ->> 'tax')::bigint,
      coalesce((g.value ->> 'gross')::bigint, (g.value ->> 'net')::bigint + (g.value ->> 'tax')::bigint)${ctx.has("taxLines", "discount") ? ", coalesce((g.value ->> 'discount')::bigint, 0)" : ""}
    from jsonb_array_elements(v_data -> 'taxLines') g;
  end if;`
    : "";

  return `
-- The import target of the quote entity (ADR 0141): item.data is { number,
-- status?, title?, currency, validUntil?, createdAt?, sentAt?, viewedAt?,
-- decidedAt?, decidedBy?, decisionNote?, company?, contact?, origin?,
-- pricesIncludeTax?, attrs?, legalEntityId?, buyer?, lines, taxLines?,
-- totals? }. A quote that is already imported is kept as it is.
create or replace function ${fn("import_quote")}(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType} := (import_quote.item ->> 'tenant')::${ctx.idType};
  v_data jsonb := import_quote.item -> 'data';
  v_number text := nullif(btrim(v_data ->> 'number'), '');
  v_made jsonb;
  v_id uuid;
  v_row ${t("quotes")};
  v_warnings jsonb := '[]'::jsonb;
  v_computed jsonb;
  v_given jsonb;
begin
  if import_quote.subject_id is not null then
    select * into v_row from ${t("quotes")} y where y.${q("id")} = import_quote.subject_id::uuid and y.${q("tenant")} = v_tenant;
    if not found then
      ${fail("IMPORT_ITEM_INVALID", "the quote no longer exists", "22023")}
    end if;
    return jsonb_build_object('subjectId', v_row.${q("id")}::text, 'updatedAt', v_row.${q("updatedAt")}, 'warnings', jsonb_build_array(jsonb_build_object('code', 'IMPORT_DOCUMENT_CHANGED', 'message', 'the source quote changed after it was imported; an imported quote is kept as imported, so import the correction as a new quote')));
  end if;
  if v_number is null then
    ${fail("IMPORT_ITEM_INVALID", "a quote needs its number", "22023")}
  end if;
  if coalesce(v_data ->> 'status', 'draft') not in ('draft', 'sent', 'viewed', 'accepted', 'rejected', 'changes_requested', 'expired', 'withdrawn') then
    ${fail("IMPORT_ITEM_INVALID", "status is draft, sent, viewed, accepted, rejected, changes_requested, expired or withdrawn", "22023")}
  end if;
  if jsonb_typeof(v_data -> 'lines') is distinct from 'array' or jsonb_array_length(v_data -> 'lines') = 0 then
    ${fail("IMPORT_ITEM_INVALID", "a quote needs at least one line", "22023")}
  end if;
  perform set_config('better_supabase.fixed_number', 'quote' || chr(31) || v_number, true);
  v_made := ${fn("create_quote")}(v_tenant, coalesce(v_data -> 'attrs', '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
    'title', coalesce(nullif(v_data ->> 'title', ''), 'Quote ' || v_number),
    'currency', v_data -> 'currency',
    'validUntil', v_data -> 'validUntil',
    'terms', v_data -> 'terms',
    'note', v_data -> 'note',
    'company', v_data -> 'company',
    'contact', v_data -> 'contact',
    'origin', v_data -> 'origin',
    'pricesIncludeTax', v_data -> 'pricesIncludeTax',
    'discountBps', v_data -> 'discountBps',
    'discountAmount', v_data -> 'discountAmount',
    'depositBps', v_data -> 'depositBps',
    'depositAmount', v_data -> 'depositAmount')), v_data -> 'lines');
  perform set_config('better_supabase.fixed_number', '', true);
  v_id := (v_made ->> ${sqlString(plain(q("id")))})::uuid;
  update ${t("quotes")} y set
    ${sets.join(",\n    ")}
  where y.${q("id")} = v_id;${taxLines}${totals}
  select * into v_row from ${t("quotes")} y where y.${q("id")} = v_id;
  return jsonb_build_object('subjectId', v_id::text, 'updatedAt', v_row.${q("updatedAt")}, 'warnings', v_warnings);
end;
$$;
${serviceGrant(`${fn("import_quote")}(uuid, jsonb, text)`)}

-- When a quote last changed, for the conflict check of imports.
create or replace function ${fn("quote_updated_at")}(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select y.${q("updatedAt")} from ${t("quotes")} y where y.${q("id")} = $1::uuid
$$;
${serviceGrant(`${fn("quote_updated_at")}(text)`)}
`;
}

/** What `contributes.imports` returns: the quote target. */
export function quoteImportTargets(
  own: BlockSqlContext,
): readonly ImportTargetContribution[] {
  return [
    {
      entity: "quote",
      subjectType: "quote",
      write: plain(own.fn("import_quote")),
      updatedAt: plain(own.fn("quote_updated_at")),
    },
  ];
}
