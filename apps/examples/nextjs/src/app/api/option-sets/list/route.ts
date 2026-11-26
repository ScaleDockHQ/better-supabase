import { optionSetList } from "@/features/option-sets/option-sets-list";
import { getOptionSetPage } from "@/features/option-sets/option-sets-queries";
import { bsb } from "@/lib/supabase/server";

/**
 * `GET /api/option-sets/list?q=&subjectType=&field=&sort=&after=`: one page of
 * option sets with the count per record type and field, read as the caller so
 * RLS decides the rows.
 */
export const GET = bsb.route(
  async (request, { db, tenant }) => {
    const query = optionSetList.parse(request.nextUrl.searchParams);

    return Response.json(await getOptionSetPage(db, tenant, query.value));
  },
  { requireTenant: true, permission: "option_sets.read" },
);
