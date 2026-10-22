import { customerList } from "../../../../lib/lists";
import { bsb } from "../../../../lib/supabase/server";

/**
 * `GET /api/customers/list?q=&status=&sort=&page=`: one page plus the count per
 * status, as two parallel requests.
 */
export const GET = bsb.route((request, { db }) => {
  const query = customerList.parse(request.nextUrl.searchParams);

  if (!query.ok) {
    return Response.json({ issues: query.issues }, { status: 400 });
  }

  return customerList.run(db, query.value, {
    select: ["id", "name", "status"],
  });
});
