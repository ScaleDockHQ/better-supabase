import { movementList } from "@/features/inventory/inventory-list";
import { getMovementPage } from "@/features/inventory/inventory-queries";
import { bsb } from "@/lib/supabase/server";

/**
 * `GET /api/inventory/movements/list?q=&kind=&location=&sort=&after=`: one page
 * of ledger movements, searched, filtered and sorted by the inventory block's
 * page methods. The inventory.read row policies decide what the caller sees.
 */
export const GET = bsb.route(
  async (request, { db, tenant }) => {
    const query = movementList.parse(request.nextUrl.searchParams);

    return Response.json((await getMovementPage(db, tenant, query.value)).page);
  },
  { requireTenant: true },
);
