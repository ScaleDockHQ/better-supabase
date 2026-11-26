import "server-only";
import { cacheTag } from "next/cache";

import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

export interface IdentityRow {
  readonly id: string;
  readonly kind: "chat" | "email";
  readonly provider: string | null;
  readonly value: string;
  readonly source: "link" | "verified_email";
}

/** The email addresses and chat accounts linked to the signed-in user. */
export async function getIdentities(): Promise<readonly IdentityRow[]> {
  "use cache: private";
  const { auth, db } = await bsb.cached();
  cacheTag(tags.identities());

  if (auth.kind !== "user") {
    return [];
  }

  const identities = await db.$blocks.identities.list().orThrow();

  return identities.map((identity) => ({
    id: identity.id,
    kind: identity.kind,
    provider: identity.provider,
    value: identity.value,
    source: identity.source,
  }));
}
