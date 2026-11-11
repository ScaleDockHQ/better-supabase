import "server-only";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import { getMembers } from "@/features/organization/organization-queries";
import { bsb } from "@/lib/supabase/server";

import { SALES_TAG } from "../sales-cache";

export interface MemberOption {
  readonly userId: string;
  readonly name: string;
}

/** The organization's members by user id, for owner, seller and queue pickers. */
export async function loadMemberOptions(): Promise<readonly MemberOption[]> {
  "use cache: private";
  const { session } = await bsb.cached();
  cacheTag(SALES_TAG);
  const tenant = tenantOf(session);

  if (!tenant) {
    return [];
  }

  const members = await getMembers(tenant);

  return members.map((member) => ({
    userId: member.userId,
    name: member.name ?? member.email ?? member.userId,
  }));
}
