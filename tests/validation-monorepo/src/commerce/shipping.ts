import type { Db } from "../runtime/index.ts";

/** Where a customer's orders ship to, primary address first. */
export function shippingAddresses(db: Db, customerId: string) {
  return db.locations.findMany({
    select: ["id", "label", "city", "isPrimary"],
    where: { customerId },
    orderBy: [{ isPrimary: "desc" }, { label: "asc" }],
  });
}
