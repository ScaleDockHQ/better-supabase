import type { Db } from "@better-supabase/example-monorepo-runtime";

/** The address an invoice goes to: the customer's primary location. */
export function billingAddress(db: Db, customerId: string) {
  return db.locations.findFirst({
    select: ["label", "city"],
    where: { customerId, isPrimary: true },
  });
}

/** Billable seats: the organization's customers that aren't archived. */
export function billableCustomers(db: Db, organizationId: string) {
  return db.customers.count({
    where: { organizationId, status: { neq: "archived" } },
  });
}
