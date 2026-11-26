import { stockList } from "@/features/inventory/inventory-list";
import { getStockPage } from "@/features/inventory/inventory-queries";
import { bsb } from "@/lib/supabase/server";

/**
 * `GET /api/inventory/levels/list?q=&status=&location=&sort=&after=`: one page
 * of stock levels, searched, filtered and sorted by the inventory block's page
 * methods. The inventory.read row policies decide what the caller sees.
 */
export const GET = bsb.route(
  async (request, { db, tenant }) => {
    const query = stockList.parse(request.nextUrl.searchParams);

    return Response.json(await getStockPage(db, tenant, query.value));
  },
  { requireTenant: true },
);
