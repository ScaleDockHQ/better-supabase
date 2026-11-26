import "server-only";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import { tags } from "@/lib/supabase/generated.tags";
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
 * (`service_accounts.read`). A failed read throws, so it is never cached and
 * Retry reads again. `null` without an organization.
 */
export async function getServicePrincipals(): Promise<
  readonly ServicePrincipalRow[] | null
> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(tags.servicePrincipals());
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const listed = await db.serviceAccounts.principalPage({
    organizationId: tenant,
    limit: 100,
  });

  if (!listed.ok) {
    throw new Error(listed.error.message);
  }

  return listed.data.items.map((principal) => ({
    id: principal.id,
    name: principal.name,
    role: principal.role,
    isDefault: principal.isDefault,
    createdAt: principal.createdAt.toString(),
    disabledAt: principal.disabledAt?.toString() ?? null,
  }));
}
