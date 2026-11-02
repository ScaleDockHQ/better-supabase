import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** What every `checkout_session.*` event carries. */
export interface CheckoutSessionEventData {
  readonly organizationId: string;
  readonly id: string;
  readonly cartId: string;
  /** `acp` or `ucp`. */
  readonly protocol: string;
  /** `open`, `ready`, `completed` or `canceled`. */
  readonly status: string;
}

/** What `checkout_session.completed` carries. */
export interface CheckoutSessionCompletedEventData extends CheckoutSessionEventData {
  readonly orderId: string;
}

/** What every `agent_mandate.*` event carries. */
export interface AgentMandateEventData {
  readonly organizationId: string;
  readonly id: string;
  /** `mandate.checkout.open.1` or `mandate.checkout.1`. */
  readonly vct: string;
  readonly sessionId: string | null;
}

/** The events of the `agent-checkout` block: type to data. */
export type AgentCheckoutEvents = {
  readonly "checkout_session.created": CheckoutSessionEventData;
  readonly "checkout_session.updated": CheckoutSessionEventData;
  readonly "checkout_session.completed": CheckoutSessionCompletedEventData;
  readonly "agent_mandate.created": AgentMandateEventData;
  readonly "agent_mandate.consumed": AgentMandateEventData;
  readonly "agent_mandate.revoked": AgentMandateEventData;
};

/**
 * The `agent-checkout` block's event types, for its manifest and
 * `onBlockEvent`.
 */
export const agentCheckoutEvents: Events<AgentCheckoutEvents> = defineEvents({
  "checkout_session.created": event<CheckoutSessionEventData>(),
  "checkout_session.updated": event<CheckoutSessionEventData>(),
  "checkout_session.completed": event<CheckoutSessionCompletedEventData>(),
  "agent_mandate.created": event<AgentMandateEventData>(),
  "agent_mandate.consumed": event<AgentMandateEventData>(),
  "agent_mandate.revoked": event<AgentMandateEventData>(),
});
