import "server-only";
import { blocks } from "@/lib/blocks";
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

/** One customer with its notes; `null` when RLS hides it or it is gone. */
export async function getCustomer(id: string) {
  "use cache: private";
  const { db, supabase } = await bs.cached();
  const customer = await db.customers
    .findUnique({
      where: { id },
      select: ["id", "name", "status", "logoPath", "createdAt"],
      include: {
        notes: {
          select: ["id", "body", "kind", "createdAt"],
          orderBy: { createdAt: "desc" },
          limit: 5,
        },
      },
    })
    .orThrow();
  if (!customer) return null;
  return {
    ...customer,
    logoUrl: customer.logoPath
      ? logos.connect(supabase).publicUrl(customer.logoPath).data
      : null,
  };
}

export interface CustomerComment {
  readonly id: string;
  readonly authorId: string | null;
  readonly body: string;
  /** ISO 8601. */
  readonly createdAt: string;
}

/** Newest first, from the comments SQL module. */
export async function getCustomerComments(
  organizationId: string,
  customerId: string,
): Promise<readonly CustomerComment[]> {
  "use cache: private";
  const { supabase } = await bs.cached();
  const comments = await blocks(supabase)
    .comments.list(organizationId, "customer", customerId)
    .orThrow();
  return comments
    .filter((comment) => comment.deletedAt === undefined)
    .map((comment) => ({
      id: comment.id,
      authorId: comment.authorId ?? null,
      body: comment.body,
      createdAt: comment.createdAt.toString(),
    }))
    .toReversed();
}
