import {
  defineBucket,
  type StorageClient,
  type TransformOptions,
} from 'better-supabase/storage';

export const IMAGE_TYPES = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
} as const;

export type ImageType = keyof typeof IMAGE_TYPES;

export const avatars = defineBucket({
  id: 'avatars',
  path: '{userId}/avatar.{ext}',
  public: true,
  policy: 'owner',
  fileSizeLimit: '5MiB',
  allowedMimeTypes: Object.keys(IMAGE_TYPES),
});

export function avatarPath(userId: string, type: ImageType): string {
  return avatars.path({ userId, ext: IMAGE_TYPES[type] });
}

/** Paths a previous upload may have used, for cleanup after replacing an avatar. */
export function leftoverAvatarPaths(userId: string, keep: string): string[] {
  return Object.values(IMAGE_TYPES)
    .map((ext) => avatars.path({ userId, ext }))
    .filter((path) => path !== keep);
}

/**
 * Rewrites a public avatar URL of this project onto the image transformer.
 * Provider pictures, rendered URLs and anything else pass through unchanged.
 */
export function avatarRenderer(storage: StorageClient, projectUrl: string) {
  const bucket = avatars.connect(storage);
  const origin = new URL(projectUrl).origin;
  const prefix = `/storage/v1/object/public/${avatars.id}/`;
  return (value: string, transform: TransformOptions): string => {
    if (!URL.canParse(value)) return value;
    const url = new URL(value);
    if (url.origin !== origin || !url.pathname.startsWith(prefix)) return value;
    const path = decodeURIComponent(url.pathname.slice(prefix.length));
    if (!avatars.match(path)) return value;
    const rendered = new URL(bucket.publicUrl(path, { transform }));
    for (const [name, param] of url.searchParams) {
      if (!rendered.searchParams.has(name))
        rendered.searchParams.set(name, param);
    }
    return rendered.href;
  };
}
