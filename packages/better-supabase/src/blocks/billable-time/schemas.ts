import type { EntitySchema } from "../entity-schema.ts";
import type { InvoiceFromTimeInput, TimeRateInput } from "./billable-time.ts";

import { entitySchema, moneyField } from "../entity-schema.ts";

/** What `setRate` takes, with the bounds the SQL checks. */
export const timeRateInputSchema: EntitySchema<TimeRateInput> =
  entitySchema<TimeRateInput>({
    title: "TimeRateInput",
    fields: {
      rate: moneyField,
      cost: { ...moneyField, optional: true },
      userId: { kind: "uuid", optional: true },
      subject: {
        kind: "json",
        optional: true,
        description: "The record the rate applies to: `{ type, id }`.",
      },
      effectiveFrom: { kind: "plainDate", optional: true },
    },
  });

/** What the section's `invoice` write takes: the record is the scope. */
export type TimeInvoiceSectionInput = Pick<
  InvoiceFromTimeInput,
  "title" | "currency" | "groupBy" | "note"
>;

export const timeInvoiceSectionInputSchema: EntitySchema<TimeInvoiceSectionInput> =
  entitySchema<TimeInvoiceSectionInput>({
    title: "TimeInvoiceSectionInput",
    fields: {
      title: { kind: "string", optional: true, minLength: 1, maxLength: 200 },
      currency: { kind: "string", optional: true, minLength: 3, maxLength: 3 },
      groupBy: {
        kind: "enum",
        values: ["subject", "member", "entry"],
        optional: true,
      },
      note: { kind: "string", optional: true, maxLength: 2000 },
    },
  });

/** What the section's `setRate` write takes: the record is the rate's subject. */
export type TimeRateSectionInput = Omit<TimeRateInput, "subject">;

export const timeRateSectionInputSchema: EntitySchema<TimeRateSectionInput> =
  entitySchema<TimeRateSectionInput>({
    title: "TimeRateSectionInput",
    fields: {
      rate: moneyField,
      cost: { ...moneyField, optional: true },
      userId: { kind: "uuid", optional: true },
      effectiveFrom: { kind: "plainDate", optional: true },
    },
  });
