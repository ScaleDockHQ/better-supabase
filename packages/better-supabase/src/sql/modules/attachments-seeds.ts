import type { BlockSqlContext } from "../context.ts";
import type { BlockSeeds, SeedTable } from "../seeds.ts";

import { typesOn } from "./attachments-documents.ts";

interface DocumentTypeSeed {
  readonly key: string;
  readonly name: string;
  readonly fields: Readonly<Record<string, Record<string, unknown>>>;
}

/**
 * The types a file in most organizations is one of. The field keys follow
 * `attachment_schema_error`: a `type` of text, number, amount, date, expiry,
 * boolean or select, and `required` on the ones a record must carry.
 */
const TYPES: readonly DocumentTypeSeed[] = [
  {
    key: "contract",
    name: "Contract",
    fields: {
      counterparty: { type: "text", required: true },
      signed_on: { type: "date" },
      expires_on: { type: "expiry" },
    },
  },
  {
    key: "invoice",
    name: "Invoice",
    fields: {
      number: { type: "text", required: true },
      issued_on: { type: "date" },
      amount: { type: "amount" },
    },
  },
  {
    key: "receipt",
    name: "Receipt",
    fields: {
      merchant: { type: "text" },
      paid_on: { type: "date" },
      amount: { type: "amount" },
    },
  },
  {
    key: "identity",
    name: "Identity document",
    fields: { number: { type: "text" }, expires_on: { type: "expiry" } },
  },
  { key: "report", name: "Report", fields: {} },
  { key: "other", name: "Other", fields: {} },
];

/**
 * `attachments.seeds`: the document types every organization starts with. The
 * drive uses the same types for its files. Nothing is seeded in custom mode,
 * where the app keeps no types table.
 */
export const attachmentsSeeds: BlockSeeds = {
  defaults: (ctx: BlockSqlContext): readonly SeedTable[] => {
    if (!typesOn(ctx)) {
      return [];
    }

    const d = (column: string): string => ctx.col("documentTypes", column);

    return [
      {
        table: ctx.table("documentTypes"),
        tenantColumn: d("tenant"),
        key: [d("key")],
        rows: TYPES.map((type) => ({
          values: {
            [d("key")]: type.key,
            [d("name")]: type.name,
            [d("fields")]: { json: type.fields },
          },
        })),
      },
    ];
  },
};
