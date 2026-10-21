import type {
  Bucket,
  BucketConfig,
  BucketPolicy,
  TransformOptions,
} from "./bucket.ts";

import { defineBucket } from "./bucket.ts";

/** The image types browsers display everywhere. */
export const IMAGE_TYPES: readonly string[] = [
  "image/png",
  "image/jpeg",
  "image/webp",
  "image/gif",
  "image/avif",
];

export interface ImageBucketOptions<
  P extends string,
  Id extends string,
  V extends string = never,
> {
  readonly id?: Id;
  /** The path template; keep the preset's placeholders the policy relies on. */
  readonly path?: P | readonly [P, ...P[]];
  /** Defaults to `true`: images load from their public URL without signing. */
  readonly public?: boolean;
  readonly fileSizeLimit?: string | number;
  readonly allowedMimeTypes?: readonly string[];
  /** Replaces the preset's policy. */
  readonly policy?: BucketPolicy;
  /** Replaces the preset's variants. */
  readonly variants?: Readonly<Record<V, TransformOptions>>;
}

export type AvatarBucketOptions<
  P extends string,
  Id extends string,
  V extends string = never,
> = ImageBucketOptions<P, Id, V>;

export interface OrganizationLogoBucketOptions<
  P extends string,
  Id extends string,
  V extends string = never,
> extends ImageBucketOptions<P, Id, V> {
  /**
   * The permission that may upload, replace and delete a logo, checked through
   * the access contract. Defaults to `organization.update`, the `organizations`
   * module's update permission.
   */
  readonly permission?: string;
  /**
   * The tenant segment connected clients are held to. `false` lets one client
   * upload for any organization the policy allows. Defaults to `{ param:
   * 'organizationId' }`.
   */
  readonly tenant?: BucketConfig["tenant"] | false;
}

const AVATAR_PATH = "{userId}/avatar-{version}.{ext}";
const LOGO_PATH = "{organizationId}/logo-{version}.{ext}";

/** The variant names of the image presets. */
export type ImageVariant = "sm" | "md" | "lg";

/** Square center crops: 48, 96 and 256 pixels. */
const AVATAR_VARIANTS: Readonly<Record<ImageVariant, TransformOptions>> = {
  sm: { width: 48, height: 48, resize: "cover" },
  md: { width: 96, height: 96, resize: "cover" },
  lg: { width: 256, height: 256, resize: "cover" },
};

/** The whole logo fitted in a 64, 128 or 256 pixel square. */
const LOGO_VARIANTS: Readonly<Record<ImageVariant, TransformOptions>> = {
  sm: { width: 64, height: 64, resize: "contain" },
  md: { width: 128, height: 128, resize: "contain" },
  lg: { width: 256, height: 256, resize: "contain" },
};

/**
 * A bucket for profile pictures: `{userId}/avatar-{version}.{ext}`, public, 2
 * MiB of images, written only by their owner (the `owner` policy). Variants
 * `sm`, `md` and `lg` are 48, 96 and 256 pixel square crops.
 */
export function avatarBucket<
  const P extends string = typeof AVATAR_PATH,
  const Id extends string = "avatars",
  const V extends string = ImageVariant,
>(options: AvatarBucketOptions<P, Id, V> = {}): Bucket<P, Id, V> {
  return defineBucket<P, Id, V>({
    // SAFETY: without options.id, Id is its default.
    id: options.id ?? ("avatars" as Id),
    // SAFETY: without options.path, P is its default.
    path: options.path ?? (AVATAR_PATH as P),
    public: options.public ?? true,
    fileSizeLimit: options.fileSizeLimit ?? "2MiB",
    allowedMimeTypes: options.allowedMimeTypes ?? IMAGE_TYPES,
    policy: options.policy ?? "owner",
    // SAFETY: without options.variants, V is its default.
    variants:
      options.variants ?? (AVATAR_VARIANTS as Record<V, TransformOptions>),
  });
}

/**
 * A bucket for organization logos: `{organizationId}/logo-{version}.{ext}`,
 * public, 2 MiB of images, written by members with the update permission
 * through the access contract (`tenant_ids_with`), so it follows the app's
 * roles. Variants `sm`, `md` and `lg` fit the whole logo in a 64, 128 or 256
 * pixel square.
 */
export function organizationLogoBucket<
  const P extends string = typeof LOGO_PATH,
  const Id extends string = "organization-logos",
  const V extends string = ImageVariant,
>(options: OrganizationLogoBucketOptions<P, Id, V> = {}): Bucket<P, Id, V> {
  const permission = options.permission ?? "organization.update";

  const tenant =
    options.tenant === false
      ? undefined
      : (options.tenant ?? { param: "organizationId" });

  return defineBucket<P, Id, V>({
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
    // SAFETY: without options.variants, V is its default.
    variants:
      options.variants ?? (LOGO_VARIANTS as Record<V, TransformOptions>),
    ...(tenant ? { tenant } : {}),
  });
}
