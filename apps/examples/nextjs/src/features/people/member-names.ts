import "server-only";
import type { bsb } from "@/lib/supabase/server";

import { readMembers } from "@/features/organization/organization-queries";

/**
 * The names of an organization's members by user id, for a loader that already
 * runs in a private scope. A member without a name shows their email.
 */
export async function readMemberNames(
  scope: Awaited<ReturnType<typeof bsb.cached>>,
  organizationId: string,
): Promise<ReadonlyMap<string, string>> {
  const members = await readMembers(scope, organizationId);

  return new Map(
    members.map((member) => [
      member.userId,
      member.name ?? member.email ?? member.userId,
    ]),
  );
}
