import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** A lease as its events carry it. */
export interface LeaseEventData {
  readonly organizationId: string;
  readonly id: string;
  readonly unitId: string;
  readonly partyType: string;
  readonly partyId: string;
  readonly status: "draft" | "active" | "ended" | "terminated";
  /** An ISO date. */
  readonly startsOn: string;
  readonly endsOn: string | null;
  /** Minor units per period, as text. */
  readonly rent: string;
  readonly currency: string;
}

/** `lease.charged`: one rent period posted on the ledger. */
export interface LeaseChargedEventData {
  readonly organizationId: string;
  readonly id: string;
  readonly leaseId: string;
  readonly periodStart: string;
  readonly periodEnd: string;
  readonly amount: string;
  readonly currency: string;
  readonly transactionId: string;
}

/** `lease.paid`: a rent payment posted on the ledger. */
export interface LeasePaidEventData {
  readonly organizationId: string;
  /** The lease. */
  readonly id: string;
  readonly transactionId: string;
  readonly amount: string;
  readonly currency: string;
}

/** The events of the `leases` block: type to data. */
export type LeasesEvents = {
  readonly "lease.created": LeaseEventData;
  readonly "lease.activated": LeaseEventData;
  readonly "lease.renewed": LeaseEventData;
  readonly "lease.terminated": LeaseEventData;
  readonly "lease.charged": LeaseChargedEventData;
  readonly "lease.paid": LeasePaidEventData;
};

/** The `leases` block's event types, for its manifest and `onBlockEvent`. */
export const leasesEvents: Events<LeasesEvents> = defineEvents({
  "lease.created": event<LeaseEventData>(),
  "lease.activated": event<LeaseEventData>(),
  "lease.renewed": event<LeaseEventData>(),
  "lease.terminated": event<LeaseEventData>(),
  "lease.charged": event<LeaseChargedEventData>(),
  "lease.paid": event<LeasePaidEventData>(),
});
