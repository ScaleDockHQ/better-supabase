import type { BlockSqlContext } from "../context.ts";

import { declared } from "../line-items-sql.ts";
import { fail } from "../shared.ts";

/** The module's context when it is installed and its tables exist. */
export function source(
  ctx: BlockSqlContext,
  module: string,
): BlockSqlContext | undefined {
  return ctx.installed(module) && ctx.of(module).mode !== "custom"
    ? ctx.of(module)
    : undefined;
}

/**
 * The legal entity column legal-entities adds to a module's table, if
 * `options.on` names it.
 */
export function hasEntityColumn(ctx: BlockSqlContext, key: string): boolean {
  return ctx.of("legal-entities").list("on", []).includes(key);
}

/** `x.<column>` of a table, or a typed null when the table lacks the column. */
export function column(
  ctx: BlockSqlContext,
  table: string,
  alias: string,
  logical: string,
  type: string,
): string {
  return declared(ctx, table, logical)
    ? `${alias}.${ctx.col(table, logical)}`
    : `null::${type}`;
}

export const isoDate = (expression: string): string =>
  `to_char(${expression}, 'YYYY-MM-DD')`;

export const isoInstant = (expression: string): string =>
  `to_char(${expression} at time zone 'UTC', 'YYYY-MM-DD')`;

export const money = (expression: string): string =>
  `(${expression})::bigint::text`;

export const quantity = (expression: string): string =>
  `trim_scale((${expression})::numeric)::text`;

export const EMPTY_ADDRESS =
  '\'{"line1":null,"line2":null,"postalCode":null,"city":null,"region":null,"country":null}\'::jsonb';

const EMPTY_TOTALS = [
  "listTotal",
  "discountTotal",
  "subtotal",
  "taxTotal",
  "total",
  "paidTotal",
  "creditedTotal",
  "shippingTotal",
  "fee",
  "balance",
];

/** A `totals` object: the keys given, null for the rest. */
export function totals(values: Readonly<Record<string, string>>): string {
  const pairs = EMPTY_TOTALS.map(
    (key) => `'${key}', ${values[key] ?? "null::text"}`,
  );

  return `jsonb_build_object(${pairs.join(", ")})`;
}

const PAYMENT_TERM_KEYS = [
  "code",
  "name",
  "days",
  "dueOn",
  "discountBps",
  "discountDays",
  "discountDueOn",
  "discountAmount",
];

/** A `payment_terms` object: the keys given, null for the rest. */
export function terms(values: Readonly<Record<string, string>>): string {
  const pairs = PAYMENT_TERM_KEYS.map(
    (key) => `'${key}', ${values[key] ?? "null::text"}`,
  );

  return `jsonb_build_object(${pairs.join(", ")})`;
}

/**
 * Qualifies the bare \`tenant\` parameter with the function's name, so a column
 * an app names \`tenant\` can never take its place.
 */
export function qualified(sql: string, name: string): string {
  return sql
    .replaceAll(/[=] tenant\b/g, `= ${name}.tenant`)
    .replaceAll("(tenant, ", `(${name}.tenant, `);
}

/** The pieces every type's function shares. */
export interface Parts {
  readonly ctx: BlockSqlContext;
  readonly fn: (name: string) => string;
  readonly idType: string;
}

export const notFound: string = fail(
  "DOCUMENT_NOT_FOUND",
  "document not found",
  "P0002",
);

/**
 * The whole payload: the six sections each type fills, joined with the document
 * header.
 */
export function payload(sections: {
  readonly document: string;
  readonly entity: string;
  readonly buyer: string;
  readonly lines: string;
  readonly taxLines: string;
  readonly totals: string;
  readonly paymentTerms: string;
  readonly shipping?: string;
}): string {
  return `jsonb_build_object(
    'document', ${sections.document},
    'entity', ${sections.entity},
    'buyer', ${sections.buyer},
    'lines', ${sections.lines},
    'tax_lines', ${sections.taxLines},
    'totals', ${sections.totals},
    'payment_terms', ${sections.paymentTerms}${sections.shipping === undefined ? "" : `,\n    'shipping', ${sections.shipping}`}
  )`;
}

/** `document` keys: the common ones, then the type's own. */
export function header(values: Readonly<Record<string, string>>): string {
  const keys = [
    "id",
    "type",
    "number",
    "title",
    "status",
    "date",
    "currency",
    "language",
    "note",
    "reference",
  ];

  const pairs = [
    ...keys.map((key) => `'${key}', ${values[key] ?? "null::text"}`),
    ...Object.entries(values)
      .filter(([key]) => !keys.includes(key))
      .map(([key, value]) => `'${key}', ${value}`),
  ];

  return `jsonb_build_object(${pairs.join(", ")})`;
}
