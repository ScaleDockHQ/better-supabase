import "server-only";
import { tenantOf } from "better-supabase/next";

import { bsb } from "@/lib/supabase/server";

export interface ServicePrincipalRow {
  readonly id: string;
  readonly name: string;
  readonly role: string;
  readonly isDefault: boolean;
  readonly createdAt: string;
  readonly disabledAt: string | null;
}

/**
 * The organization's service principals through the block's read policy
 * (`service_principals.read`). A failed read throws, so it is never cached and
 * Retry reads again. `null` without an organization.
 */
export async function loadServicePrincipals(): Promise<
  readonly ServicePrincipalRow[] | null
> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const listed = await db.serviceAccounts.list(tenant);

  if (!listed.ok) {
    throw new Error(listed.error.message);
  }

  return listed.data.map((principal) => ({
    id: principal.id,
    name: principal.name,
    role: principal.role,
    isDefault: principal.isDefault,
    createdAt: principal.createdAt.toString(),
    disabledAt: principal.disabledAt?.toString() ?? null,
  }));
}
