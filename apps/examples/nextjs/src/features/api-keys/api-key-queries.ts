import "server-only";
import { blocks } from "@/lib/blocks";
import { bs } from "@/lib/supabase/server";

export interface ApiKeyRow {
  readonly id: string;
  readonly name: string;
  /** What the token starts with, to recognize it. */
  readonly prefix: string;
  readonly personal: boolean;
  /** ISO 8601 strings: Temporal values don't cross into Client Components. */
  readonly createdAt: string;
  readonly lastUsedAt: string | null;
  readonly revokedAt: string | null;
}

/** The keys the caller can see in the organization (the api-keys SQL module). */
export async function getApiKeys(
  organizationId: string,
): Promise<readonly ApiKeyRow[]> {
  "use cache: private";
  const { supabase } = await bs.cached();
  const keys = await blocks(supabase).apiKeys.list(organizationId).orThrow();
  return keys.map((key) => ({
    id: key.id,
    name: key.name,
    prefix: `${key.prefix}_${key.publicId}`,
    personal: key.userId !== undefined,
    createdAt: key.createdAt.toString(),
    lastUsedAt: key.lastUsedAt?.toString() ?? null,
    revokedAt: key.revokedAt?.toString() ?? null,
  }));
}
