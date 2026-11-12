import { lotList, lotSpec } from "@/features/inventory/inventory-list";
import { readLotRows } from "@/features/inventory/inventory-queries";
import { pageBlockRows } from "@/lib/block-list";
import { bsb } from "@/lib/supabase/server";

/**
 * `GET /api/inventory/lots/list?q=&expiry=&location=&sort=&after=`: one page of
 * lots, searched, filtered and sorted on the server. The inventory.read row
 * policies decide what the caller sees.
 */
export const GET = bsb.route(
  async (request, { db, tenant }) => {
    const { rows } = await readLotRows(db, tenant);
    const query = lotList.parse(request.nextUrl.searchParams);

    return Response.json(pageBlockRows(lotList, lotSpec, rows, query.value));
  },
  { requireTenant: true },
);
