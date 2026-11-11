import type { CustomerRow } from "../../../../features/customers/customer-row";

import { customerList } from "../../../../lib/lists";
import { bsbCore as bsb } from "../../../../lib/supabase/server-core";

/**
 * `GET /api/customers/list?q=&status=&sort=&after=`: one page of customer rows
 * plus the count per status, as two parallel requests. The overview calls it
 * for every URL state but the default page the server renders.
 */
export const GET = bsb.route((request, { db }) => {
  const query = customerList.parse(request.nextUrl.searchParams);

  if (!query.ok) {
    return Response.json({ issues: query.issues }, { status: 400 });
  }

  return customerList
    .run(db, query.value, {
      select: ["id", "name", "status", "logoPath"],
      include: {
        _count: { notes: true },
        _max: { notes: { createdAt: true } },
      },
    })
    .map((page) => ({
      items: page.items.map((customer): CustomerRow => ({
        id: customer.id,
        name: customer.name,
        status: customer.status,
        logoUrl: customer.logoPath
          ? db.$buckets.logos.publicUrl(customer.logoPath, {
              transform: "square",
            }).data
          : null,
        notes: customer._count.notes,
        lastNoteAt: customer._max.notes.createdAt,
      })),
      nextCursor: page.nextCursor,
      facetCounts: page.facetCounts,
      facetCountsCapped: page.facetCountsCapped === true,
    }));
});
