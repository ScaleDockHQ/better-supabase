import type { Db } from "@better-supabase/example-monorepo-runtime";

export function activeCustomers(db: Db) {
  return db.customers.findMany({
    select: ["id", "name", "status"],
    where: { status: "active" },
    orderBy: { name: "asc" },
  });
}

export function renameCustomer(db: Db, id: string, name: string) {
  return db.customers.update(id, { name }, { select: ["id", "name"] });
}
