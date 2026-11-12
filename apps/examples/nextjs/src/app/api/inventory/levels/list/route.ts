import { stockList, stockSpec } from "@/features/inventory/inventory-list";
import { readStockRows } from "@/features/inventory/inventory-queries";
import { pageBlockRows } from "@/lib/block-list";
import { bsb } from "@/lib/supabase/server";

/**
 * `GET /api/inventory/levels/list?q=&status=&location=&sort=&after=`: one page
 * of stock levels, searched, filtered and sorted on the server. The
 * inventory.read row policies decide what the caller sees.
 */
export const GET = bsb.route(
  async (request, { db, tenant }) => {
    const { rows } = await readStockRows(db, tenant);
    const query = stockList.parse(request.nextUrl.searchParams);

    return Response.json(
      pageBlockRows(stockList, stockSpec, rows, query.value),
    );
  },
  { requireTenant: true },
);
