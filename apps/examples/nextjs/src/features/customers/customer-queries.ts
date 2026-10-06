import "server-only";
import { logos } from "@/lib/buckets";
import { customerList } from "@/lib/lists";
import { bs } from "@/lib/supabase/server";

/**
 * The first page of the caller's customers plus the count per status.
 * `bs.cached()` queries with the user's token, so RLS decides the rows;
 * the private cache keeps them in this browser only, for as long as the
 * session view may be reused. The page doesn't read `searchParams`, so it
 * stays in the instant App Shell; filtered pages go through
 * `/api/customers/list`.
 */
export async function getCustomers() {
  "use cache: private";
  const { db, supabase } = await bs.cached();
  const page = await customerList
    .run(db, customerList.defaults, {
      select: ["id", "name", "status", "logoPath"],
      // Counted and maxed in the database, in the same request.
      include: {
        _count: { notes: true },
        _max: { notes: { createdAt: true } },
      },
    })
    .orThrow();
  // Public bucket: the URL is built locally, and `next/image` resizes it
  // through Storage (see `src/image-loader.ts`).
  const storage = logos.connect(supabase);
  return {
    ...page,
    items: page.items.map((customer) => ({
      ...customer,
      logoUrl: customer.logoPath
        ? storage.publicUrl(customer.logoPath).data
        : null,
    })),
  };
}
