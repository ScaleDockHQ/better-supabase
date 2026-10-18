import "server-only";
import { tenantOf } from "better-supabase/next";
import { notFound, unstable_rethrow } from "next/navigation";

import { can } from "@/features/user/user-permissions";
import { bs } from "@/lib/supabase/server";

const UUID = /^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$/i;

/** Each customer has one notes document, opened on first edit. */
export interface DocumentSummary {
  readonly customerId: string;
  readonly customerName: string;
  /** ISO 8601, so the cached value stays serializable. */
  readonly updatedAt: string;
}

export interface DocumentTarget {
  readonly organizationId: string;
  readonly customerId: string;
  readonly customerName: string;
  readonly canWrite: boolean;
}

export type Loaded<T> =
  | { readonly kind: "ok"; readonly data: T }
  | { readonly kind: "error" }
  | { readonly kind: "no-organization" };

/** A failed read throws, so it is never cached and Retry reads again. */
async function loadDocuments(): Promise<readonly DocumentSummary[] | null> {
  "use cache: private";
  const { session, db } = await bs.cached();

  if (!tenantOf(session)) {
    return null;
  }

  const customers = await db.customers
    .findMany({
      select: ["id", "name", "updatedAt"],
      orderBy: { name: "asc" },
      limit: 200,
    })
    .orThrow();

  return customers.map((customer) => ({
    customerId: customer.id,
    customerName: customer.name,
    updatedAt: customer.updatedAt,
  }));
}

export async function getDocuments(): Promise<
  Loaded<readonly DocumentSummary[]>
> {
  try {
    const documents = await loadDocuments();

    return documents === null
      ? { kind: "no-organization" }
      : { kind: "ok", data: documents };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}

async function loadTarget(
  customerId: string,
): Promise<DocumentTarget | "not-found" | null> {
  "use cache: private";
  const { session, db } = await bs.cached();
  const organizationId = tenantOf(session);

  if (!organizationId) {
    return null;
  }

  const customer = await db.customers
    .findFirst({ select: ["id", "name"], where: { id: customerId } })
    .orThrow();

  if (customer === null) {
    return "not-found";
  }

  return {
    organizationId,
    customerId: customer.id,
    customerName: customer.name,
    canWrite: can(session, "documents.write"),
  };
}

/** The customer whose notes document `/documents/[id]` edits. */
export async function getDocumentTarget(
  customerId: string,
): Promise<Loaded<DocumentTarget>> {
  if (!UUID.test(customerId)) {
    notFound();
  }

  let target: DocumentTarget | "not-found" | null;

  try {
    target = await loadTarget(customerId);
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }

  if (target === "not-found") {
    notFound();
  }

  return target === null
    ? { kind: "no-organization" }
    : { kind: "ok", data: target };
}
