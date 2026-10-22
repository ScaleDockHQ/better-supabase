import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** `contract.created` and `contract.updated`. */
export interface ContractEventData {
  readonly organizationId: string;
  readonly contractId: string;
  readonly title: string;
  readonly status: string;
}

/** `contract.status_changed`: the contract moved through its lifecycle. */
export interface ContractStatusChangedEventData {
  readonly organizationId: string;
  readonly contractId: string;
  readonly status: string;
  readonly previousStatus: string;
}

/** `contract.renewed`: an auto-renewing contract reached its end date. */
export interface ContractRenewedEventData {
  readonly organizationId: string;
  readonly contractId: string;
  /** The new end date, `YYYY-MM-DD`. */
  readonly endsOn: string;
  readonly renewedCount: number;
}

/** `obligation.saved` and `obligation.status_changed`. */
export interface ObligationEventData {
  readonly organizationId: string;
  readonly obligationId: string;
  readonly contractId: string;
  readonly status: string;
}

/** The events of the `contracts` block: type to data. */
export type ContractsEvents = {
  readonly "contract.created": ContractEventData;
  readonly "contract.updated": ContractEventData;
  readonly "contract.status_changed": ContractStatusChangedEventData;
  readonly "contract.renewed": ContractRenewedEventData;
  readonly "obligation.saved": ObligationEventData;
  readonly "obligation.status_changed": ObligationEventData;
};

/** The `contracts` block's event types, for its manifest and `onBlockEvent`. */
export const contractsEvents: Events<ContractsEvents> = defineEvents({
  "contract.created": event<ContractEventData>(),
  "contract.updated": event<ContractEventData>(),
  "contract.status_changed": event<ContractStatusChangedEventData>(),
  "contract.renewed": event<ContractRenewedEventData>(),
  "obligation.saved": event<ObligationEventData>(),
  "obligation.status_changed": event<ObligationEventData>(),
});
