import type { Section, SectionWrite } from "../sections.ts";
import type {
  BillableTime,
  TimeInvoice,
  TimeRate,
  UnbilledTime,
} from "./billable-time.ts";
import type {
  TimeInvoiceSectionInput,
  TimeRateSectionInput,
} from "./schemas.ts";

import { defineSection } from "../sections.ts";
import {
  timeInvoiceSectionInputSchema,
  timeRateSectionInputSchema,
} from "./schemas.ts";

/** The writes of the billable time section. */
export type BillableTimeWrites = {
  /** Sets the record's hourly rate, or a member's rate on it. */
  readonly setRate: SectionWrite<BillableTime, TimeRateSectionInput, TimeRate>;
  /** Bills the record's unbilled time on a new draft invoice. */
  readonly invoice: SectionWrite<
    BillableTime,
    TimeInvoiceSectionInput,
    TimeInvoice
  >;
};

/** A record's unbilled time, such as a project's, ready to invoice. */
export const billableTimeSection: Section<
  BillableTime,
  UnbilledTime,
  undefined,
  never,
  BillableTimeWrites
> = defineSection({
  permissions: { read: "read", write: "manage" },
  module: "billable-time",
  load: (client: BillableTime, subject) => client.unbilled({ subject }),
  events: ["time.*"],
  writes: {
    setRate: {
      input: timeRateSectionInputSchema,
      run: (client: BillableTime, subject, input: TimeRateSectionInput) =>
        client.setRate({ ...input, subject }),
    },
    invoice: {
      input: timeInvoiceSectionInputSchema,
      run: (client: BillableTime, subject, input: TimeInvoiceSectionInput) =>
        client.invoice({ ...input, subject }),
    },
  },
});
