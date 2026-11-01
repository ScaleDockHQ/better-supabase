/** The checkout protocols a session can speak: ACP and UCP. */
export const CHECKOUT_PROTOCOLS = ["acp", "ucp"] as const;

/**
 * Where a checkout session stands. `ready` means the buyer details are complete
 * and the agent may complete it.
 */
export const CHECKOUT_SESSION_STATUSES = [
  "open",
  "ready",
  "completed",
  "canceled",
] as const;

/**
 * The AP2 v0.2 checkout mandate types, matched by exact string. The open one is
 * the autonomous (intent) mandate, the closed one binds one checkout.
 */
export const AGENT_MANDATE_TYPES = [
  "mandate.checkout.open.1",
  "mandate.checkout.1",
] as const;

/** `consumed` and `revoked` are final; `active` ends at `expiresAt`. */
export const AGENT_MANDATE_STATUSES = [
  "active",
  "consumed",
  "revoked",
] as const;
