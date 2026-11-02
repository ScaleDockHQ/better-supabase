import "server-only";
import * as v from "valibot";

import { bsb } from "@/lib/supabase/server";

const Row = v.object({ name: v.string(), status: v.string() });

export interface SharedCustomer {
  readonly name: string;
  readonly status: string;
  /** ISO 8601. */
  readonly expiresAt: string | null;
}

/**
 * The customer a share link points to, for a visitor without a session.
 * `resolve` checks the token's hash, revocation and expiry; only then does the
 * service role read the two columns the page shows.
 */
export async function getSharedCustomer(
  token: string,
): Promise<SharedCustomer | null> {
  "use cache: private";
  const { db } = await bsb.cached();

  const link = await db.shareLinks.resolve({ token }).orThrow();

  if (link?.subject.type !== "customer") {
    return null;
  }

  const { data, error } = await bsb
    .admin()
    .$client.from("customers")
    .select("name, status")
    .eq("id", link.subject.id)
    .eq("organization_id", link.organizationId)
    .maybeSingle();

  if (error) {
    throw new Error(error.message);
  }

  if (!data) {
    return null;
  }

  const row = v.parse(Row, data);

  return {
    name: row.name,
    status: row.status,
    expiresAt: link.expiresAt?.toString() ?? null,
  };
}
