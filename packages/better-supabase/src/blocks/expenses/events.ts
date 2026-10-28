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
  /** Null without the approvals block (`options.approvals: false`). */
  readonly approvalId: string | null;
}

/** `expense_report.approved` and `.reimbursed`: posted on the ledger. */
export interface ExpenseReportPostedEventData extends ExpenseReportEventData {
  readonly transactionId: string;
}

export interface ExpenseEventData {
  readonly organizationId: string;
  readonly id: string;
  readonly userId: string | null;
  readonly employeeId?: string;
  readonly status:
    | "draft"
    | "submitted"
    | "approved"
    | "rejected"
    | "reimbursed";
  readonly amount: string;
  readonly currency: string;
}

/** The events of the `expenses` block: type to data. */
export type ExpensesEvents = {
  readonly "expense_report.created": ExpenseReportEventData;
  readonly "expense_report.submitted": ExpenseReportSubmittedEventData;
  readonly "expense_report.approved": ExpenseReportPostedEventData;
  readonly "expense_report.reimbursed": ExpenseReportPostedEventData;
  readonly "expense_report.cancelled": ExpenseReportEventData;
  readonly "expense_report.rejected": ExpenseReportEventData;
  readonly "expense.created": ExpenseEventData;
  readonly "expense.submitted": ExpenseEventData;
  readonly "expense.approved": ExpenseEventData;
  readonly "expense.rejected": ExpenseEventData;
  readonly "expense.reimbursed": ExpenseEventData;
};

/** The `expenses` block's event types, for its manifest and `onBlockEvent`. */
export const expensesEvents: Events<ExpensesEvents> = defineEvents({
  "expense_report.created": event<ExpenseReportEventData>(),
  "expense_report.submitted": event<ExpenseReportSubmittedEventData>(),
  "expense_report.approved": event<ExpenseReportPostedEventData>(),
  "expense_report.reimbursed": event<ExpenseReportPostedEventData>(),
  "expense_report.cancelled": event<ExpenseReportEventData>(),
  "expense_report.rejected": event<ExpenseReportEventData>(),
  "expense.created": event<ExpenseEventData>(),
  "expense.submitted": event<ExpenseEventData>(),
  "expense.approved": event<ExpenseEventData>(),
  "expense.rejected": event<ExpenseEventData>(),
  "expense.reimbursed": event<ExpenseEventData>(),
});
