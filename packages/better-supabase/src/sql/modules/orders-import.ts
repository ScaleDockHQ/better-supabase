import type { BlockSqlContext } from "../context.ts";
import type { ImportTargetContribution } from "../contributions.ts";
import type { OrdersNames } from "./orders-shared.ts";

import { sqlString } from "../../core/template.ts";
import { BILLING_PARTIES, COST_SOURCES } from "../line-items-sql.ts";
import { hasLegalEntityColumn } from "../numbering-sql.ts";
import { fail, serviceGrant } from "../shared.ts";
import { assignNumber, columns } from "./orders-shared.ts";

/** An import target names its functions as `schema.function`, without quotes. */
const plain = (qualified: string): string => qualified.replaceAll('"', "");

/**
 * The import target of the `order` entity (ADR 0141). The order is inserted as
 * it was: its number, its final status, its dates and its stored totals, with
 * no stock allocation, no events and no invoice. The payments become payment
 * rows with their original dates.
 */
export function orderImportFunctions(
  ctx: BlockSqlContext,
  names: OrdersNames,
): string {
  const { fn } = names;
  const orders = ctx.table("orders");
  const lines = ctx.table("orderLines");
  const payments = ctx.table("payments");
  const o = columns(ctx, "orders");
  const ol = columns(ctx, "orderLines");
  const p = columns(ctx, "payments");
  const has = (logical: string): boolean => ctx.has("orders", logical);
  const lineHas = (logical: string): boolean => ctx.has("orderLines", logical);

  const optional = (
    condition: boolean,
    column: string,
    value: string,
  ): readonly [string, string] | undefined =>
    condition ? [column, value] : undefined;

  const header = [
    [o("tenant"), "v_tenant"],
    [o("number"), "v_number"],
    [o("sequence"), "v_seq"],
    [o("customer"), "nullif(v_data ->> 'customerId', '')::uuid"],
    optional(
      has("email"),
      has("email") ? o("email") : "",
      "v_data ->> 'email'",
    ),
    [
      o("status"),
      ctx.cast(
        "orders",
        "status",
        "coalesce(v_data ->> 'status', 'confirmed')",
      ),
    ],
    [o("currency"), "upper(v_data ->> 'currency')"],
    [o("subtotal"), "v_subtotal"],
    [o("discountTotal"), "v_discount"],
    [o("shippingTotal"), "v_shipping"],
    [o("taxTotal"), "v_tax"],
    [o("total"), "v_total"],
    [o("paidTotal"), "v_paid"],
    [o("taxInclusive"), "v_inclusive"],
    [o("shippingAddress"), "v_data -> 'shippingAddress'"],
    optional(
      has("billingAddress"),
      has("billingAddress") ? o("billingAddress") : "",
      "v_data -> 'billingAddress'",
    ),
    [o("tax"), "v_data -> 'taxLines'"],
    [o("invoiceNumber"), "nullif(v_data ->> 'invoiceNumber', '')"],
    [
      o("invoiceSequence"),
      "substring(nullif(v_data ->> 'invoiceNumber', '') from '([0-9]+)$')::bigint",
    ],
    [o("invoicedAt"), "nullif(v_data ->> 'invoicedAt', '')::timestamptz"],
    [
      o("placedAt"),
      "coalesce(nullif(v_data ->> 'placedAt', '')::timestamptz, now())",
    ],
    [
      o("paidAt"),
      "coalesce(nullif(v_data ->> 'paidAt', '')::timestamptz, v_paid_at)",
    ],
    [o("fulfilledAt"), "nullif(v_data ->> 'fulfilledAt', '')::timestamptz"],
    [o("completedAt"), "nullif(v_data ->> 'completedAt', '')::timestamptz"],
    [o("cancelledAt"), "nullif(v_data ->> 'cancelledAt', '')::timestamptz"],
    optional(
      has("cancelReason"),
      has("cancelReason") ? o("cancelReason") : "",
      "nullif(v_data ->> 'cancelReason', '')",
    ),
    optional(
      has("buyer"),
      has("buyer") ? o("buyer") : "",
      "case when jsonb_typeof(v_data -> 'buyer') = 'object' then v_data -> 'buyer' end",
    ),
    ...(hasLegalEntityColumn(ctx, "orders")
      ? [
          [
            "legal_entity_id",
            "nullif(v_data ->> 'legalEntityId', '')::uuid",
          ] as const,
        ]
      : []),
  ].filter((entry): entry is readonly [string, string] => entry !== undefined);

  const lineColumns = [
    [ol("tenant"), "v_tenant"],
    [ol("order"), "v_id"],
    [ol("position"), "e.n::integer"],
    [ol("variant"), "nullif(e.l ->> 'variantId', '')::uuid"],
    [ol("product"), "nullif(e.l ->> 'productId', '')::uuid"],
    [ol("sku"), "coalesce(e.l ->> 'sku', '')"],
    [ol("title"), "e.l ->> 'title'"],
    [ol("quantity"), "(e.l ->> 'quantity')::integer"],
    [ol("unitAmount"), "(e.l ->> 'unitAmount')::bigint"],
    [
      ol("subtotal"),
      "coalesce((e.l ->> 'subtotal')::bigint, (e.l ->> 'unitAmount')::bigint * (e.l ->> 'quantity')::bigint)",
    ],
    [ol("discount"), "coalesce((e.l ->> 'discount')::bigint, 0)"],
    [ol("tax"), "coalesce((e.l ->> 'tax')::bigint, 0)"],
    [
      ol("total"),
      "coalesce((e.l ->> 'total')::bigint, (e.l ->> 'unitAmount')::bigint * (e.l ->> 'quantity')::bigint - coalesce((e.l ->> 'discount')::bigint, 0))",
    ],
    [
      ol("requiresShipping"),
      "coalesce((e.l ->> 'requiresShipping')::boolean, false)",
    ],
    [ol("location"), "nullif(e.l ->> 'locationId', '')::uuid"],
    ...(
      [
        ["taxCodeId", "nullif(e.l ->> 'taxCodeId', '')::uuid"],
        ["unitCost", "(e.l ->> 'unitCost')::bigint"],
        ["costSource", "nullif(e.l ->> 'costSource', '')"],
        ["binId", "nullif(e.l ->> 'binId', '')::uuid"],
        [
          "billingParty",
          "coalesce(nullif(e.l ->> 'billingParty', ''), 'customer')",
        ],
        ["billingPartyId", "nullif(e.l ->> 'billingPartyId', '')"],
        ["billingAccountId", "nullif(e.l ->> 'billingAccountId', '')::uuid"],
      ] as const
    )
      .filter(([logical]) => lineHas(logical))
      .map(([logical, value]) => [ol(logical), value] as const),
  ];

  return `
-- The import target of the order entity (ADR 0141): item.data is { number,
-- status?, currency, customerId?, email?, taxInclusive?, placedAt?, paidAt?,
-- fulfilledAt?, completedAt?, cancelledAt?, shippingAddress?, billingAddress?,
-- buyer?, legalEntityId?, taxLines?, totals?, lines, payments? }. A line is {
-- variantId?, productId?, sku?, title, quantity, unitAmount, discount?, tax?,
-- locationId?, taxCodeId?, unitCost?, costSource?, binId?, billingParty?,
-- billingPartyId?, billingAccountId? }; a line without a variant is free
-- text. Amounts are minor units as text. totals is { subtotal, discountTotal,
-- shippingTotal, taxTotal, total } and is kept as given; a difference from
-- the lines is a warning. An order that is already imported is kept.
create or replace function ${fn("import_order")}(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType} := (import_order.item ->> 'tenant')::${ctx.idType};
  v_data jsonb := import_order.item -> 'data';
  v_number text := nullif(btrim(v_data ->> 'number'), '');
  v_seq bigint;
  v_id uuid;
  v_inclusive boolean := coalesce((v_data ->> 'taxInclusive')::boolean, false);
  v_subtotal bigint;
  v_discount bigint;
  v_tax bigint;
  v_shipping bigint;
  v_total bigint;
  v_paid bigint := 0;
  v_paid_at timestamptz;
  v_given jsonb := v_data -> 'totals';
  v_warnings jsonb := '[]'::jsonb;
  v_updated timestamptz;
  v_pay jsonb;
  v_index integer := 0;
begin
  if import_order.subject_id is not null then
    select x.${o("updatedAt")} into v_updated from ${orders} x where x.${o("id")} = import_order.subject_id::uuid and x.${o("tenant")} = v_tenant;
    if not found then
      ${fail("IMPORT_ITEM_INVALID", "the order no longer exists", "22023")}
    end if;
    return jsonb_build_object('subjectId', import_order.subject_id, 'updatedAt', v_updated, 'warnings', jsonb_build_array(jsonb_build_object('code', 'IMPORT_DOCUMENT_CHANGED', 'message', 'the source order changed after it was imported; an imported order is kept as imported')));
  end if;
  if v_number is null then
    ${fail("IMPORT_ITEM_INVALID", "an order needs its number", "22023")}
  end if;
  if coalesce(v_data ->> 'currency', '') !~ '^[A-Za-z]{3}$' then
    ${fail("IMPORT_ITEM_INVALID", "currency is an ISO 4217 code", "22023")}
  end if;
  if jsonb_typeof(v_data -> 'lines') is distinct from 'array' or jsonb_array_length(v_data -> 'lines') = 0 then
    ${fail("IMPORT_ITEM_INVALID", "an order needs at least one line", "22023")}
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_data -> 'lines') l
    where coalesce(l.value ->> 'title', '') = '' or coalesce(l.value ->> 'quantity', '') !~ '^[1-9][0-9]{0,8}$' or coalesce(l.value ->> 'unitAmount', '') !~ '^[0-9]{1,18}$'
  ) then
    ${fail("IMPORT_ITEM_INVALID", "a line needs a title, a whole quantity above zero and a unitAmount", "22023")}
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_data -> 'lines') l
    where l.value ->> 'billingParty' is not null and l.value ->> 'billingParty' not in (${BILLING_PARTIES.map(sqlString).join(", ")})
      or l.value ->> 'costSource' is not null and l.value ->> 'costSource' not in (${COST_SOURCES.map(sqlString).join(", ")})
  ) then
    ${fail("IMPORT_ITEM_INVALID", "a line's billingParty or costSource is not a known value", "22023")}
  end if;

  select coalesce(sum((l.value ->> 'unitAmount')::bigint * (l.value ->> 'quantity')::bigint), 0),
    coalesce(sum(coalesce((l.value ->> 'discount')::bigint, 0)), 0),
    coalesce(sum(coalesce((l.value ->> 'tax')::bigint, 0)), 0)
  into v_subtotal, v_discount, v_tax
  from jsonb_array_elements(v_data -> 'lines') l;
  v_shipping := coalesce((v_given ->> 'shippingTotal')::bigint, 0);
  v_total := v_subtotal - v_discount + v_shipping + case when v_inclusive then 0 else v_tax end;
  if jsonb_typeof(v_given) = 'object' then
    if coalesce((v_given ->> 'subtotal')::bigint, v_subtotal) <> v_subtotal
      or coalesce((v_given ->> 'discountTotal')::bigint, v_discount) <> v_discount
      or coalesce((v_given ->> 'taxTotal')::bigint, v_tax) <> v_tax
      or coalesce((v_given ->> 'total')::bigint, v_total) <> v_total then
      v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_TOTALS_MISMATCH', 'message', 'the stored totals differ from the totals computed from the lines; the stored totals were kept',
        'computed', jsonb_build_object('subtotal', v_subtotal::text, 'discountTotal', v_discount::text, 'taxTotal', v_tax::text, 'total', v_total::text),
        'given', v_given));
    end if;
    v_subtotal := coalesce((v_given ->> 'subtotal')::bigint, v_subtotal);
    v_discount := coalesce((v_given ->> 'discountTotal')::bigint, v_discount);
    v_tax := coalesce((v_given ->> 'taxTotal')::bigint, v_tax);
    v_total := coalesce((v_given ->> 'total')::bigint, v_total);
  end if;
  if jsonb_typeof(v_data -> 'payments') = 'array' then
    select coalesce(sum((p.value ->> 'amount')::bigint), 0), max((p.value ->> 'paidAt')::timestamptz)
    into v_paid, v_paid_at from jsonb_array_elements(v_data -> 'payments') p;
  end if;

  if nullif(btrim(v_data ->> 'number'), '') is not null then
    perform set_config('better_supabase.fixed_number', 'order' || chr(31) || btrim(v_data ->> 'number'), true);
  end if;
  ${assignNumber(ctx, "order", "v_tenant", { seq: "v_seq", number: "v_number" })}
  insert into ${orders} (${header.map(([column]) => column).join(", ")})
  values (${header.map(([, value]) => value).join(", ")})
  returning ${o("id")}, ${o("updatedAt")} into v_id, v_updated;

  insert into ${lines} (${lineColumns.map(([column]) => column).join(", ")})
  select ${lineColumns.map(([, value]) => value).join(", ")}
  from jsonb_array_elements(v_data -> 'lines') with ordinality as e(l, n);

  if jsonb_typeof(v_data -> 'payments') = 'array' then
    for v_pay in select e.value from jsonb_array_elements(v_data -> 'payments') e loop
      v_index := v_index + 1;
      insert into ${payments} (${p("tenant")}, ${p("order")}, ${p("provider")}, ${p("reference")}, ${p("status")}, ${p("currency")}, ${p("amount")}, ${p("captured")}, ${p("refunded")}, ${p("createdAt")}, ${p("updatedAt")})
      values (v_tenant, v_id, coalesce(nullif(v_pay ->> 'provider', ''), 'import'),
        coalesce(nullif(v_pay ->> 'reference', ''), import_order.item ->> 'key' || ':payment:' || v_index::text),
        ${ctx.value("payments", "status", "succeeded")}, upper(v_data ->> 'currency'), (v_pay ->> 'amount')::bigint, (v_pay ->> 'amount')::bigint, 0,
        coalesce(nullif(v_pay ->> 'paidAt', '')::timestamptz, now()), coalesce(nullif(v_pay ->> 'paidAt', '')::timestamptz, now()));
    end loop;
  end if;
  return jsonb_build_object('subjectId', v_id::text, 'updatedAt', v_updated, 'warnings', v_warnings);
end;
$$;
${serviceGrant(`${fn("import_order")}(uuid, jsonb, text)`)}

-- When an order last changed, for the conflict check of imports.
create or replace function ${fn("order_updated_at")}(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select x.${o("updatedAt")} from ${orders} x where x.${o("id")} = $1::uuid
$$;
${serviceGrant(`${fn("order_updated_at")}(text)`)}
`;
}

/** What `contributes.imports` returns: the order target. */
export function orderImportTargets(
  own: BlockSqlContext,
): readonly ImportTargetContribution[] {
  return [
    {
      entity: "order",
      subjectType: "order",
      write: plain(own.fn("import_order")),
      updatedAt: plain(own.fn("order_updated_at")),
    },
  ];
}
