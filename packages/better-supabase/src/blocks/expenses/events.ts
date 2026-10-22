import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** An expense report as its events carry it. */
export interface ExpenseReportEventData {
  readonly organizationId: string;
  readonly id: string;
  /** The member who spent the money. */
  readonly userId: string;
  readonly status:
    | "draft"
    | "submitted"
    | "approved"
    | "rejected"
    | "reimbursed"
    | "cancelled";
  /** Minor units, as text. */
  readonly total: string;
  readonly currency: string;
}

/** `expense_report.submitted`: the report went to approval. */
export interface ExpenseReportSubmittedEventData extends ExpenseReportEventData {
  readonly approvalId: string;
}

/** `expense_report.approved` and `.reimbursed`: posted on the ledger. */
export interface ExpenseReportPostedEventData extends ExpenseReportEventData {
  readonly transactionId: string;
}

/** The events of the `expenses` block: type to data. */
export type ExpensesEvents = {
  readonly "expense_report.created": ExpenseReportEventData;
  readonly "expense_report.submitted": ExpenseReportSubmittedEventData;
  readonly "expense_report.approved": ExpenseReportPostedEventData;
  readonly "expense_report.reimbursed": ExpenseReportPostedEventData;
  readonly "expense_report.cancelled": ExpenseReportEventData;
};

/** The `expenses` block's event types, for its manifest and `onBlockEvent`. */
export const expensesEvents: Events<ExpensesEvents> = defineEvents({
  "expense_report.created": event<ExpenseReportEventData>(),
  "expense_report.submitted": event<ExpenseReportSubmittedEventData>(),
  "expense_report.approved": event<ExpenseReportPostedEventData>(),
  "expense_report.reimbursed": event<ExpenseReportPostedEventData>(),
  "expense_report.cancelled": event<ExpenseReportEventData>(),
});
