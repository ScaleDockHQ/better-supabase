import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { fail, SERVICE_CALLER } from "../shared.ts";
import { OPERATIONS } from "./permissions-model.ts";
import { partyRows } from "./procurement-sql.ts";

/** A block context of another module, when it is installed and not custom. */
function linked(
  ctx: BlockSqlContext,
  module: string,
): BlockSqlContext | undefined {
  return ctx.installed(module) && ctx.of(module).mode !== "custom"
    ? ctx.of(module)
    : undefined;
}

/** The SQL pieces the rfqs files share. */
export interface RfqsSql {
  readonly fn: (name: string) => string;
  /** A column of the rfqs table. */
  readonly q: (column: string) => string;
  /** A column of the lines table. */
  readonly l: (column: string) => string;
  /** A column of the suppliers table. */
  readonly s: (column: string) => string;
  /** A column of the quotes table. */
  readonly k: (column: string) => string;
  /** A column of the quote lines table. */
  readonly u: (column: string) => string;
  readonly rfqs: string;
  readonly lines: string;
  readonly suppliers: string;
  readonly quotes: string;
  readonly quoteLines: string;
  readonly read: string;
  readonly write: string;
  readonly manage: string;
  readonly allowed: (tenant: string, permission: string) => string;
  readonly invalid: (message: string) => string;
  readonly forbidden: (message: string) => string;
  readonly status: (message: string) => string;
  readonly rfqMissing: string;
  readonly quoteMissing: string;
  readonly invitationMissing: string;
  /** The inventory block's context, when it is installed and not custom. */
  readonly inventory: BlockSqlContext | undefined;
  /** PL/pgSQL that refuses a supplier contacts does not list as active. */
  readonly supplierCheck: (id: string, tenant: string) => string;
  readonly rfqJson: (row: string) => string;
  readonly lineJson: (row: string) => string;
  readonly supplierJson: (row: string) => string;
  readonly quoteJson: (row: string) => string;
  readonly quoteLineJson: (row: string) => string;
  /** Records a `rfq.*` event of an rfqs row. */
  readonly recordRfq: (type: string, row: string, summary: string) => string;
  /** Records a `rfq_quote.*` event of a quotes row of the rfq `rfq`. */
  readonly recordQuote: (
    type: string,
    row: string,
    rfq: string,
    summary: string,
  ) => string;
}

export function rfqsSql(ctx: BlockSqlContext): RfqsSql {
  const q = (column: string): string => ctx.col("rfqs", column);
  const l = (column: string): string => ctx.col("lines", column);
  const s = (column: string): string => ctx.col("suppliers", column);
  const k = (column: string): string => ctx.col("quotes", column);
  const u = (column: string): string => ctx.col("quoteLines", column);

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or (${tenant} is not null and ${ctx.can("tenant", tenant, permission)}))`;

  const supplierRows = partyRows(ctx, "p_id", "p_tenant", [
    "roles",
    "supplierStatus",
  ]);

  return {
    fn: (name) => ctx.fn(name),
    q,
    l,
    s,
    k,
    u,
    rfqs: ctx.table("rfqs"),
    lines: ctx.table("lines"),
    suppliers: ctx.table("suppliers"),
    quotes: ctx.table("quotes"),
    quoteLines: ctx.table("quoteLines"),
    read: ctx.permission("read", OPERATIONS["rfqs.read"]),
    write: ctx.permission("write", OPERATIONS["rfqs.write"]),
    manage: ctx.permission("manage", OPERATIONS["rfqs.manage"]),
    allowed,
    invalid: (message) => fail("RFQ_INVALID", message, "22023"),
    forbidden: (message) => fail("RFQ_FORBIDDEN", message),
    status: (message) => fail("RFQ_STATUS", message, "55000"),
    rfqMissing: fail("RFQ_NOT_FOUND", "no such request for quotation", "P0002"),
    quoteMissing: fail("RFQ_QUOTE_NOT_FOUND", "no such quote", "P0002"),
    invitationMissing: fail(
      "RFQ_SUPPLIER_NOT_FOUND",
      "no such invited supplier",
      "P0002",
    ),
    inventory: linked(ctx, "inventory"),
    supplierCheck: (id, tenant) => {
      if (supplierRows === undefined) {
        return "";
      }

      const rows = supplierRows
        .replaceAll("p_id", id)
        .replaceAll("p_tenant", tenant);

      return `
  if not exists (select 1 from (${rows}) s(roles, status) where (s.roles is null or cardinality(s.roles) = 0 or 'supplier' = any(s.roles)) and s.status is distinct from 'blocked') then
    ${fail("RFQ_SUPPLIER_INVALID", "the supplier is not an active supplier in contacts", "22023")}
  end if;`;
    },
    rfqJson: (row) =>
      `jsonb_build_object('id', ${row}.${q("id")}, 'organizationId', ${row}.${q("tenant")}, 'number', ${row}.${q("number")}, 'title', ${row}.${q("title")}, 'status', ${row}.${q("status")}, 'currency', ${row}.${q("currency")}, 'dueAt', ${row}.${q("dueAt")}, 'notes', ${row}.${q("notes")}, 'awardedQuoteId', ${row}.${q("awardedQuote")}, 'purchaseOrderId', ${row}.${q("purchaseOrder")}, 'cancelReason', ${row}.${q("cancelReason")}, 'openedAt', ${row}.${q("openedAt")}, 'closedAt', ${row}.${q("closedAt")}, 'awardedAt', ${row}.${q("awardedAt")}, 'createdBy', ${row}.${q("createdBy")}, 'createdAt', ${row}.${q("createdAt")}, 'updatedAt', ${row}.${q("updatedAt")})`,
    lineJson: (row) =>
      `jsonb_build_object('id', ${row}.${l("id")}, 'rfqId', ${row}.${l("rfq")}, 'ordinal', ${row}.${l("ordinal")}, 'description', ${row}.${l("description")}, 'variantId', ${row}.${l("variant")}, 'quantity', ${row}.${l("quantity")}, 'unit', ${row}.${l("unit")})`,
    supplierJson: (row) =>
      `jsonb_build_object('id', ${row}.${s("id")}, 'rfqId', ${row}.${s("rfq")}, 'supplierType', ${row}.${s("supplierType")}, 'supplierId', ${row}.${s("supplierId")}, 'status', ${row}.${s("status")}, 'invitedAt', ${row}.${s("invitedAt")}, 'respondedAt', ${row}.${s("respondedAt")})`,
    quoteJson: (row) =>
      `jsonb_build_object('id', ${row}.${k("id")}, 'rfqId', ${row}.${k("rfq")}, 'invitationId', ${row}.${k("invitation")}, 'status', ${row}.${k("status")}, 'currency', (select x.${q("currency")} from ${ctx.table("rfqs")} x where x.${q("id")} = ${row}.${k("rfq")}), 'total', ${row}.${k("total")}::text, 'leadTimeDays', ${row}.${k("leadTimeDays")}, 'validUntil', ${row}.${k("validUntil")}, 'notes', ${row}.${k("notes")}, 'revision', ${row}.${k("revision")}, 'submittedBy', ${row}.${k("submittedBy")}, 'submittedAt', ${row}.${k("submittedAt")}, 'updatedAt', ${row}.${k("updatedAt")})`,
    quoteLineJson: (row) =>
      `jsonb_build_object('id', ${row}.${u("id")}, 'quoteId', ${row}.${u("quote")}, 'lineId', ${row}.${u("line")}, 'unitAmount', ${row}.${u("unitAmount")}::text, 'leadTimeDays', ${row}.${u("leadTimeDays")})`,
    recordRfq: (type, row, summary) =>
      ctx.record({
        type,
        payload: `jsonb_build_object('organizationId', ${row}.${q("tenant")}, 'id', ${row}.${q("id")}, 'number', ${row}.${q("number")}, 'status', ${row}.${q("status")}, 'quoteId', ${row}.${q("awardedQuote")}, 'purchaseOrderId', ${row}.${q("purchaseOrder")})`,
        subject: `'rfqs/' || ${row}.${q("id")}::text`,
        tenant: `${row}.${q("tenant")}`,
        audit: {
          category: "data",
          targetType: "rfq",
          recordId: `${row}.${q("id")}::text`,
          targetLabel: `${row}.${q("number")}`,
          summary: sqlString(summary),
        },
      }),
    recordQuote: (type, row, rfq, summary) =>
      ctx.record({
        type,
        payload: `jsonb_build_object('organizationId', ${row}.${k("tenant")}, 'id', ${row}.${k("id")}, 'rfqId', ${row}.${k("rfq")}, 'invitationId', ${row}.${k("invitation")}, 'total', ${row}.${k("total")}::text)`,
        subject: `'rfqs/' || ${row}.${k("rfq")}::text`,
        tenant: `${row}.${k("tenant")}`,
        audit: {
          category: "data",
          targetType: "rfq",
          recordId: `${row}.${k("rfq")}::text`,
          targetLabel: `${rfq}.${q("number")}`,
          summary: sqlString(summary),
        },
      }),
  };
}
