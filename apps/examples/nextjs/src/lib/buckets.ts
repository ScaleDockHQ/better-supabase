import { defineBucket } from "better-supabase/storage";

import { buckets } from "./supabase/generated.ts";

/** `{organizationId}/{customerId}/logo/{version}.webp`, readable within the tenant. */
export const logos = defineBucket(buckets.customerLogos);

/** `{userId}/avatar-{version}.{ext}`, public, written only by the user. */
export const avatars = defineBucket(buckets.avatars);

/** The image an avatar shows: the uploaded object, else the provider's picture. */
export function avatarSrc(
  storage: ReturnType<typeof avatars.connect>,
  row: {
    readonly avatarPath: string | null;
    readonly avatarUrl: string | null;
  },
): string | null {
  if (row.avatarPath) return storage.publicUrl(row.avatarPath).data ?? null;
  return row.avatarUrl;
}
