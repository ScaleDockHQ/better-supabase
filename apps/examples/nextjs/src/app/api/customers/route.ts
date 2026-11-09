import { bsbCore } from "../../../lib/supabase/server-core";

export const GET = bsbCore.route((request, { db }) => {
  const search = request.nextUrl.searchParams.get("q");

  return db.customers.list({
    select: ["id", "name", "status", "organizationId"],
    where: search ? { name: { ilike: `%${search}%` } } : {},
    orderBy: { name: "asc" },
    limit: 50,
  });
});
