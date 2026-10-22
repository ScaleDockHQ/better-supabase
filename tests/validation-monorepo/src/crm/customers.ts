import type { Db } from "../runtime/index.ts";

export function activeCustomers(db: Db) {
  return db.customers.list({
    select: ["id", "name", "status"],
    where: { status: "active" },
    orderBy: { name: "asc" },
    limit: 50,
  });
}

export function customerById(db: Db, id: string) {
  return db.customers.get(id, { select: ["id", "name", "status"] });
}
