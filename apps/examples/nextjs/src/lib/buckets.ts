import { defineBucket } from "better-supabase/storage";

import { buckets } from "./supabase/generated.ts";

/**
 * `{organizationId}/{customerId}/logo/{version}.webp`, readable within the
 * tenant. `square` crops the center, so `next/image` keeps it square at every
 * width.
 */
export const logos = defineBucket({
  ...buckets.customerLogos,
  variants: { square: { width: 56, height: 56, resize: "cover" } },
});

/** `{userId}/avatar-{version}.{ext}`, public, written only by the user. */
export const avatars = defineBucket({
  ...buckets.avatars,
  variants: {
    sm: { width: 32, height: 32, resize: "cover" },
    md: { width: 64, height: 64, resize: "cover" },
  },
});

/** The image an avatar shows: the uploaded object, else the provider's picture. */
export function avatarSrc(
  storage: Pick<ReturnType<typeof avatars.connect>, "publicUrl">,
  row: {
    readonly avatarPath: string | null;
    readonly avatarUrl: string | null;
  },
): string | null {
  if (row.avatarPath) {
    return storage.publicUrl(row.avatarPath, { transform: "sm" }).data ?? null;
  }

  return row.avatarUrl;
}
