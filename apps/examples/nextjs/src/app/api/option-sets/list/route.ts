import { loadAdminList } from "../../../../features/admin-lists/admin-list-load";
import { optionSetList } from "../../../../features/option-sets/option-sets-list";
import { optionSetSource } from "../../../../features/option-sets/option-sets-source";
import { bsbCore as bsb } from "../../../../lib/supabase/server-core";

/**
 * `GET /api/option-sets/list?q=&state=&sort=&after=`: one page of option sets
 * with the count per state, read as the caller so RLS decides the rows.
 */
export const GET = bsb.route(
  async (request, { session, tenant }) => {
    const query = optionSetList.parse(request.nextUrl.searchParams);

    if (!query.ok) {
      return Response.json({ issues: ["invalid list state"] }, { status: 400 });
    }

    return Response.json(
      await loadAdminList({
        session,
        tenant,
        list: optionSetList,
        source: optionSetSource,
        access: "user",
        query: query.value,
      }),
    );
  },
  { requireTenant: true, permission: "option_sets.read" },
);
