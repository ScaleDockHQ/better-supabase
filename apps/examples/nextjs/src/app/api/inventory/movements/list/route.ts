import {
  movementList,
  movementSpec,
} from "@/features/inventory/inventory-list";
import { readMovementRows } from "@/features/inventory/inventory-queries";
import { pageBlockRows } from "@/lib/block-list";
import { bsb } from "@/lib/supabase/server";

/**
 * `GET /api/inventory/movements/list?q=&kind=&location=&sort=&after=`: one page
 * of ledger movements, searched, filtered and sorted on the server. The
 * inventory.read row policies decide what the caller sees.
 */
export const GET = bsb.route(
  async (request, { db, tenant }) => {
    const { rows } = await readMovementRows(db, tenant);
    const query = movementList.parse(request.nextUrl.searchParams);

    return Response.json(
      pageBlockRows(movementList, movementSpec, rows, query.value),
    );
  },
  { requireTenant: true },
);
