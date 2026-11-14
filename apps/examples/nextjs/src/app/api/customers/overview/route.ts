import { readCustomerRows } from "../../../../features/customers-list/customers-reads";
import { customersList } from "../../../../lib/supabase/pages/customers.list";
import { bsbCore as bsb } from "../../../../lib/supabase/server-core";

/**
 * `GET /api/customers/overview?q=&status=&sort=&after=`: one page of customer
 * rows plus the count per status, as two parallel requests. The overview calls
 * it for every URL state but the default page the server renders.
 * `/api/customers/list` is the generated route (ADR 0859) with the raw page.
 */
export const GET = bsb.route(async (request, { db }) => {
  const query = customersList.parse(request.nextUrl.searchParams);

  if (!query.ok) {
    return Response.json({ issues: query.issues }, { status: 400 });
  }

  return Response.json(await readCustomerRows(db, query.value));
});
