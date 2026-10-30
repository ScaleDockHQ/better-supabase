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
