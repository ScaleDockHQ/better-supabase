import type { Bucket, BucketConfig, BucketPolicy } from "./bucket.ts";

import { defineBucket } from "./bucket.ts";

/** The image types browsers display everywhere. */
export const IMAGE_TYPES: readonly string[] = [
  "image/png",
  "image/jpeg",
  "image/webp",
  "image/gif",
  "image/avif",
];

export interface ImageBucketOptions<P extends string, Id extends string> {
  readonly id?: Id;
  /** The path template; keep the preset's placeholders the policy relies on. */
  readonly path?: P | readonly [P, ...P[]];
  /** Defaults to `true`: images load from their public URL without signing. */
  readonly public?: boolean;
  readonly fileSizeLimit?: string | number;
  readonly allowedMimeTypes?: readonly string[];
  /** Replaces the preset's policy. */
  readonly policy?: BucketPolicy;
}

export type AvatarBucketOptions<
  P extends string,
  Id extends string,
> = ImageBucketOptions<P, Id>;

export interface OrgLogoBucketOptions<
  P extends string,
  Id extends string,
> extends ImageBucketOptions<P, Id> {
  /**
   * The permission that may upload, replace and delete a logo, checked
   * through the access contract. Defaults to `organization.update`, the
   * `organizations` module's update permission.
   */
  readonly permission?: string;
  /**
   * The tenant segment connected clients are held to. `false` lets one
   * client upload for any organization the policy allows. Defaults to
   * `{ param: 'orgId' }`.
   */
  readonly tenant?: BucketConfig["tenant"] | false;
}

const AVATAR_PATH = "{userId}/avatar-{version}.{ext}";
const LOGO_PATH = "{orgId}/logo-{version}.{ext}";

/**
 * A bucket for profile pictures: `{userId}/avatar-{version}.{ext}`, public,
 * 2 MiB of images, written only by their owner (the `owner` policy).
 */
export function avatarBucket<
  const P extends string = typeof AVATAR_PATH,
  const Id extends string = "avatars",
>(options: AvatarBucketOptions<P, Id> = {}): Bucket<P, Id> {
  return defineBucket<P, Id>({
    // SAFETY: without options.id, Id is its default.
    id: options.id ?? ("avatars" as Id),
    // SAFETY: without options.path, P is its default.
    path: options.path ?? (AVATAR_PATH as P),
    public: options.public ?? true,
    fileSizeLimit: options.fileSizeLimit ?? "2MiB",
    allowedMimeTypes: options.allowedMimeTypes ?? IMAGE_TYPES,
    policy: options.policy ?? "owner",
  });
}

/**
 * A bucket for organization logos: `{orgId}/logo-{version}.{ext}`, public,
 * 2 MiB of images, written by members with the update permission through
 * the access contract (`tenant_ids_with`), so it follows the app's roles.
 */
export function orgLogoBucket<
  const P extends string = typeof LOGO_PATH,
  const Id extends string = "organization-logos",
>(options: OrgLogoBucketOptions<P, Id> = {}): Bucket<P, Id> {
  const permission = options.permission ?? "organization.update";
  const tenant =
    options.tenant === false
      ? undefined
      : (options.tenant ?? { param: "orgId" });
  return defineBucket<P, Id>({
    // SAFETY: without options.id, Id is its default.
    id: options.id ?? ("organization-logos" as Id),
    // SAFETY: without options.path, P is its default.
    path: options.path ?? (LOGO_PATH as P),
    public: options.public ?? true,
    fileSizeLimit: options.fileSizeLimit ?? "2MiB",
    allowedMimeTypes: options.allowedMimeTypes ?? IMAGE_TYPES,
    policy: options.policy ?? {
      access: { read: permission, write: permission },
    },
    ...(tenant ? { tenant } : {}),
  });
}
