/** The roles `options.roles` falls back to. */
export const PARTY_ROLES = [
  "customer",
  "supplier",
  "funder",
  "partner",
] as const;

/** Where a supplier stands on the approved supplier list. */
export const SUPPLIER_STATUSES = [
  "approved",
  "conditional",
  "blocked",
] as const;

export type SupplierStatus = (typeof SUPPLIER_STATUSES)[number];

/** How a credit limit acts: not at all, as a warning, or as a refusal. */
export const CREDIT_BLOCKS = ["none", "soft", "hard"] as const;

export type CreditBlock = (typeof CREDIT_BLOCKS)[number];

/** The channels a document can be delivered through. */
export const DELIVERY_CHANNELS = ["email", "post", "portal"] as const;

export type DeliveryChannel = (typeof DELIVERY_CHANNELS)[number];
