import type { BlockSqlContext } from "../context.ts";
import type { QuoteNames } from "./quotes-functions.ts";

import { sqlString } from "../../core/template.ts";
import {
  declared,
  documentTotals,
  lineColumn,
  lineFieldsJson,
  TOTAL_COLUMNS,
} from "../line-items-sql.ts";
import { int8Text } from "../money-sql.ts";
import { columnsObject, fail } from "../shared.ts";
import { subjectInTenant } from "../subject-check-sql.ts";

/** Whether the quotes table has both columns of a company or contact link. */
export function quoteParty(
  ctx: BlockSqlContext,
  party: "company" | "contact",
): boolean {
  return ctx.has("quotes", `${party}Type`) && ctx.has("quotes", `${party}Id`);
}

/** Whether the quotes table has both columns of the record it was made from. */
export function quoteOrigin(ctx: BlockSqlContext): boolean {
  return ctx.has("quotes", "originType") && ctx.has("quotes", "originId");
}

/**
 * SQL over quote columns prefixed with `prefix` (`""` in a policy, `v_row.` in
 * a function) that is true when the caller is a guest the quote is shared with:
 * a grant on the quote, or a guest of its company or contact (ADR 0070). A
 * guest never sees a draft. `"false"` when guests aren't set up.
 */
export function quoteGuest(
  ctx: BlockSqlContext,
  n: QuoteNames,
  prefix: string,
): string {
  const q = (column: string): string => `${prefix}${n.c("quotes", column)}`;

  const checks = [
    ctx.scope.guest(q("tenant"), "'quote'", `${q("id")}::text`, "read"),
    ...(["company", "contact"] as const)
      .filter((party) => quoteParty(ctx, party))
      .map((party) =>
        ctx.scope.guestParty(q("tenant"), q(`${party}Type`), q(`${party}Id`)),
      ),
  ].filter((check) => check !== "false");

  return checks.length === 0
    ? "false"
    : `(${ctx.is("quotes", "status", q("status"), ["draft"], true)} and (${checks.join(" or ")}))`;
}

/** The SQL helpers every quote function shares. */
export interface QuoteKit {
  readonly q: (column: string) => string;
  readonly l: (column: string) => string;
  readonly has: (logical: string) => boolean;
  /** Whether the line table has logical column `logical`. */
  readonly lineHas: (logical: string) => boolean;
  /** A column of row, or null when the app maps it to null. */
  readonly or: (row: string, logical: string) => string;
  /** ", <column>" for an insert's column list, when the column exists. */
  readonly also: (logical: string) => string;
  /** Value when the column exists, for valueLines(). */
  readonly present: (logical: string, value: string) => string | undefined;
  /** `<column> = value(<column>),` on its own line of an update's set list. */
  readonly assign: (
    logical: string,
    value: (column: string) => string,
  ) => string;
  /** The values of an insert, the present ones of each group on a line. */
  readonly valueLines: (
    indent: string,
    ...groups: readonly (string | undefined)[][]
  ) => string;
  /** Refuses a value the app's quotes table has no column for. */
  readonly refuse: (
    supported: boolean,
    given: string,
    thing: string,
    what: string,
  ) => string;
  readonly editable: (alias: string) => string;
  readonly st: (
    value: string,
    labels: readonly string[],
    negate?: boolean,
  ) => string;
  readonly sv: (label: string) => string;
  readonly open: (alias: string) => string;
  readonly lines: (alias: string) => string;
  readonly taxLines: (alias: string) => string;
  readonly row: (alias: string) => string;
  /** What a customer sees of quote `alias`: no internal note, no owner. */
  readonly publicJson: (alias: string) => string;
  readonly record: (type: string, alias: string, extra?: string) => string;
  readonly checkParty: (
    kind: "COMPANY" | "CONTACT",
    type: string,
    id: string,
    tenant: string,
  ) => string;
  readonly notifyOwner: (event: string) => string;
  /** Marks sent quote `v_row` viewed, recording `quote.viewed`. */
  readonly markViewed: () => string;
  /** The `afterTotals` of the line table: the deposit due on the total. */
  readonly depositDue: string | undefined;
}

export function quoteKit(ctx: BlockSqlContext, n: QuoteNames): QuoteKit {
  const { t, c } = n;
  const q = (column: string): string => c("quotes", column);
  const l = (column: string): string => c("lines", column);
  const company = quoteParty(ctx, "company");
  const contact = quoteParty(ctx, "contact");
  const has = (logical: string): boolean => ctx.has("quotes", logical);

  const lineHas = (logical: string): boolean => declared(ctx, "lines", logical);

  const or = (row: string, logical: string): string =>
    has(logical) ? `${row}.${q(logical)}` : "null";

  const also = (logical: string): string =>
    has(logical) ? `, ${q(logical)}` : "";

  const present = (logical: string, value: string): string | undefined =>
    has(logical) ? value : undefined;

  const assign = (
    logical: string,
    value: (column: string) => string,
  ): string =>
    has(logical) ? `\n      ${q(logical)} = ${value(q(logical))},` : "";

  const valueLines = (
    indent: string,
    ...groups: readonly (string | undefined)[][]
  ): string =>
    groups
      .map((group) => group.filter((value) => value !== undefined).join(", "))
      .filter((line) => line !== "")
      .join(`,\n${indent}`);

  const refuse = (
    supported: boolean,
    given: string,
    thing: string,
    what: string,
  ): string =>
    supported
      ? ""
      : `
  if ${given} is not null then
    ${fail(`QUOTE_${thing}_UNSUPPORTED`, `this quotes table has no ${what}`, "22023")}
  end if;`;

  const editable = (alias: string): string =>
    `(${n.service} or ${ctx.scope.can(`${alias}.${q("tenant")}`, n.write)})`;

  const st = (value: string, labels: readonly string[], negate = false) =>
    ctx.is("quotes", "status", value, labels, negate);

  const sv = (label: string): string => ctx.value("quotes", "status", label);

  const viewed = ctx.appValues("quotes", "status", "viewed").length > 0;

  const record = (type: string, alias: string, extra = ""): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', ${alias}.${q("tenant")}, 'quoteId', ${alias}.${q("id")}, 'subjectType', 'quote', 'subjectId', ${alias}.${q("id")}::text, 'identifier', ${alias}.${q("identifier")}${extra})`,
      subject: `'quotes/' || ${alias}.${q("id")}::text`,
      tenant: `${alias}.${q("tenant")}::text`,
      audit: false,
    });

  const markViewed = (): string =>
    viewed || has("viewedAt")
      ? `  if ${st(`v_row.${q("status")}`, ["sent"])}${viewed ? "" : ` and v_row.${q("viewedAt")} is null`} then
    update ${t("quotes")} x set ${viewed ? `${q("status")} = ${sv("viewed")}${has("viewedAt") ? ", " : ""}` : ""}${has("viewedAt") ? `${q("viewedAt")} = now()` : ""} where x.${q("id")} = v_row.${q("id")}
    returning * into v_row;
    ${record("quote.viewed", "v_row")}
  end if;`
      : "  null;";

  const open = (alias: string): string =>
    st(`${alias}.${q("status")}`, ["draft", "changes_requested"]);

  const lineValue = (column: string): string =>
    lineColumn(ctx, "lines", "ql", column);

  const documentLine = ["section", "optional", "selected"]
    .filter(lineHas)
    .map((column) => `, ${sqlString(column)}, ql.${l(column)}`)
    .join("");

  const lines = (alias: string): string =>
    `coalesce((select jsonb_agg(jsonb_build_object('position', ql.${l("position")}, 'description', ql.${l("description")}, 'quantity', ql.${l("quantity")}, 'unitAmount', ql.${l("unitAmount")}::text, 'discountBps', ${lineValue("discountBps")}, 'taxRateBps', ${lineValue("taxRateBps")}, 'taxCode', ${lineValue("taxCode")}${documentLine}, 'product', case when ${lineValue("productType")} is null then null else jsonb_build_object('type', ${lineValue("productType")}, 'id', ${lineValue("productId")}) end${lineFieldsJson("ql", n.lineExtras)}) order by ql.${l("position")}) from ${t("lines")} ql where ql.${l("parent")} = ${alias}.${q("id")}), '[]'::jsonb)`;

  const tl = (column: string): string => c("taxLines", column);

  const taxLines = (alias: string): string =>
    ctx.hasTable("taxLines")
      ? `coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl.${tl("taxRateBps")}, 'taxCode', ${ctx.has("taxLines", "taxCode") ? `tl.${tl("taxCode")}` : "null"}, 'net', tl.${tl("net")}::text, 'tax', tl.${tl("tax")}::text, 'gross', tl.${tl("gross")}::text, 'discount', ${ctx.has("taxLines", "discount") ? `tl.${tl("discount")}::text` : "'0'"}) order by tl.${tl("taxRateBps")}, ${ctx.has("taxLines", "taxCode") ? `tl.${tl("taxCode")}` : "1"} nulls first) from ${t("taxLines")} tl where tl.${tl("parent")} = ${alias}.${q("id")}), '[]'::jsonb)`
      : "'[]'::jsonb";

  const int8Columns = [
    "number",
    ...Object.keys(TOTAL_COLUMNS),
    "discountAmount",
    "depositDue",
  ].filter(has);

  const int8 = int8Columns.map(q);

  const int8As = Object.fromEntries(
    int8Columns.map((logical) => [
      logical,
      (value: string) => `${value}::text`,
    ]),
  );

  const row = (alias: string): string =>
    `(${ctx.rowJson("quotes", alias, { as: int8As })} - ${sqlString(q("tokenHash").replaceAll('"', ""))}${q("tokenHash") === '"token_hash"' ? "" : " - 'token_hash'"}) || ${int8Text(alias, int8)} || jsonb_build_object('lines', ${lines(alias)}, 'taxLines', ${taxLines(alias)}${
      n.extras.length === 0
        ? ""
        : `, 'fields', ${columnsObject(
            alias,
            n.extras.map((extra) => extra.name),
          )}`
    })`;

  const text = (alias: string, logical: string, otherwise: string): string =>
    has(logical) ? `${alias}.${q(logical)}::text` : otherwise;

  const publicJson = (alias: string): string => `jsonb_build_object(
    'identifier', ${alias}.${q("identifier")}, 'revision', ${alias}.${q("revision")}, 'title', ${alias}.${q("title")},
    'status', ${ctx.label("quotes", "status", `${alias}.${q("status")}`)}, 'currency', ${alias}.${q("currency")}, 'validUntil', ${alias}.${q("validUntil")},
    'terms', ${or(alias, "terms")}, 'pricesIncludeTax', ${has("pricesIncludeTax") ? `${alias}.${q("pricesIncludeTax")}` : "false"},
    'discountBps', ${has("discountBps") ? `${alias}.${q("discountBps")}` : "0"}, 'discountAmount', ${text(alias, "discountAmount", "'0'")},
    'depositBps', ${or(alias, "depositBps")}, 'depositDue', ${text(alias, "depositDue", "'0'")},
    'listTotal', ${text(alias, "listTotal", `${alias}.${q("subtotal")}::text`)}, 'subtotal', ${alias}.${q("subtotal")}::text, 'discountTotal', ${text(alias, "discountTotal", "'0'")},
    'taxTotal', ${alias}.${q("taxTotal")}::text, 'total', ${alias}.${q("total")}::text, 'lines', ${lines(alias)}, 'taxLines', ${taxLines(alias)})`;

  const checkParty = (
    kind: "COMPANY" | "CONTACT",
    type: string,
    id: string,
    tenant: string,
  ): string =>
    (kind === "COMPANY" ? company : contact)
      ? `
  if ${id} is not null and not ${subjectInTenant(ctx, type, id, tenant)} then
    ${fail(`QUOTE_${kind}_FORBIDDEN`, `the ${kind.toLowerCase()} is unknown or not readable in this organization`, "42501")}
  end if;`
      : refuse(false, id, kind, `${kind.toLowerCase()} columns`);

  const notifyOwner = (event: string): string =>
    ctx.installed("notifications")
      ? `
  if v_row.${q("owner")} is not null then
    ${ctx.notify(
      `jsonb_build_object(
      'type', ${sqlString(event)},
      'tenant', v_row.${q("tenant")},
      'subject_type', 'quote',
      'subject_id', v_row.${q("id")}::text,
      'summary', v_row.${q("identifier")} || ' ' || v_row.${q("title")},
      'recipients', jsonb_build_array(v_row.${q("owner")}),
      'key', ${sqlString(`${event}:`)} || v_row.${q("id")}::text,
      'data', jsonb_build_object('quoteId', v_row.${q("id")}, 'status', v_row.${q("status")})
    )`,
      { indent: "    " },
    )}
  end if;`
      : "";

  const total = documentTotals(ctx, {
    lines: "lines",
    parent: "quotes",
    taxLines: "taxLines",
  })
    ? "v_total"
    : "(v_list - v_discount + v_tax)";

  return {
    q,
    l,
    has,
    lineHas,
    or,
    also,
    present,
    assign,
    valueLines,
    refuse,
    editable,
    st,
    sv,
    open,
    lines,
    taxLines,
    row,
    publicJson,
    record,
    checkParty,
    notifyOwner,
    markViewed,
    depositDue:
      has("depositDue") && has("depositBps")
        ? `${q("depositDue")} = case when x.${q("depositBps")} is null then 0 else round(${total} * x.${q("depositBps")} / 10000.0)::bigint end`
        : undefined,
  };
}
