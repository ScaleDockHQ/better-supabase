import type { Db } from "@better-supabase/example-monorepo-runtime";

/** The address an invoice goes to: the customer's primary location. */
export function billingAddress(db: Db, customerId: string) {
  return db.locations.get(
    { where: { customerId, isPrimary: true } },
    { select: ["label", "city"], optional: true },
  );
}

/** Billable seats: the organization's customers that aren't archived. */
export function billableCustomers(db: Db, organizationId: string) {
  return db.customers.count({
    where: { organizationId, status: { neq: "archived" } },
  });
}
