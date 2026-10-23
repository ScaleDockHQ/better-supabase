import type { RecordBinding, RecordBindingWrite } from "../record-bindings.ts";
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

import { defineRecordBinding } from "../record-bindings.ts";
import {
  timeInvoiceSectionInputSchema,
  timeRateSectionInputSchema,
} from "./schemas.ts";

/** The writes of the billable time binding. */
export type BillableTimeWrites = {
  /** Sets the record's hourly rate, or a member's rate on it. */
  readonly setRate: RecordBindingWrite<
    BillableTime,
    TimeRateSectionInput,
    TimeRate
  >;
  /** Bills the record's unbilled time on a new draft invoice. */
  readonly invoice: RecordBindingWrite<
    BillableTime,
    TimeInvoiceSectionInput,
    TimeInvoice
  >;
};

/** A record's unbilled time, such as a project's, ready to invoice. */
export const billableTimeBinding: RecordBinding<
  BillableTime,
  UnbilledTime,
  undefined,
  never,
  BillableTimeWrites
> = defineRecordBinding({
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
