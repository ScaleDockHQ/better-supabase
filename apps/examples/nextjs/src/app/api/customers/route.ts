import { bs } from "../../../lib/supabase/server";

export const GET = bs.route((request, { db }) => {
  const search = request.nextUrl.searchParams.get("q");
  return db.customers.findMany({
    select: ["id", "name", "status", "organizationId"],
    where: search ? { name: { ilike: `%${search}%` } } : {},
    orderBy: { name: "asc" },
    limit: 50,
  });
});
