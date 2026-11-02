import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** What the `commission_plan.*` events carry. */
export interface CommissionPlanEventData {
  readonly organizationId: string;
  readonly id: string;
  readonly name: string;
  /** `flat` or `tiered`. */
  readonly kind: string;
}

/** What the `commission.*` events carry. */
export interface CommissionEventData {
  readonly organizationId: string;
  readonly id: string;
  readonly planId: string;
  readonly sellerId: string;
  /** The record the commission was earned on, such as `invoices`. */
  readonly sourceType: string;
  readonly sourceId: string;
  /** The commission in minor units, as text. */
  readonly amount: string;
  readonly currency: string;
}

/** What the `commission_statement.*` events carry. */
export interface CommissionStatementEventData {
  readonly organizationId: string;
  readonly id: string;
  readonly sellerId: string;
  readonly currency: string;
  readonly startsOn: string;
  readonly endsOn: string;
  /** The statement total in minor units, as text. */
  readonly total: string;
  readonly status: string;
}

/** The events of the `commissions` block: type to data. */
export type CommissionsEvents = {
  readonly "commission_plan.created": CommissionPlanEventData;
  readonly "commission_plan.updated": CommissionPlanEventData;
  readonly "commission.accrued": CommissionEventData;
  readonly "commission.reversed": CommissionEventData;
  readonly "commission_statement.finalized": CommissionStatementEventData;
  readonly "commission_statement.paid": CommissionStatementEventData;
};

/** The `commissions` block's event types, for its manifest and `onBlockEvent`. */
export const commissionsEvents: Events<CommissionsEvents> = defineEvents({
  "commission_plan.created": event<CommissionPlanEventData>(),
  "commission_plan.updated": event<CommissionPlanEventData>(),
  "commission.accrued": event<CommissionEventData>(),
  "commission.reversed": event<CommissionEventData>(),
  "commission_statement.finalized": event<CommissionStatementEventData>(),
  "commission_statement.paid": event<CommissionStatementEventData>(),
});
