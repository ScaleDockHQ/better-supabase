export interface StorageImageOptions {
  /** Project URL, e.g. `import.meta.env.PUBLIC_SUPABASE_URL`. */
  readonly url: string;
  /** Resize mode for the transform. Defaults to Storage's own (`cover`). */
  readonly resize?: "cover" | "contain" | "fill";
}

/** The size and quality to render an image at. */
export interface StorageImageSize {
  readonly width: number;
  readonly height?: number | undefined;
  readonly quality?: number | undefined;
}

/** Storage's image transformation limits. */
const MAX_SIDE = 2500;
const QUALITY = { min: 20, max: 100 } as const;

const clamp = (value: number, min: number, max: number): number =>
  Math.min(max, Math.max(min, Math.round(value)));

/**
 * Turns public Storage object URLs into Supabase image transformation URLs
 * (`/render/image/public`) at a given size. Any other URL (local files,
 * other hosts, signed URLs) comes back as `undefined`: a signed URL's token
 * covers the transform it was signed with, so sign it with `renderUrl()`.
 *
 * ```ts
 * const imageUrl = storageImageUrl({ url: SUPABASE_URL })
 * imageUrl(avatar, { width: 96 }) ?? avatar
 * ```
 */
export function storageImageUrl(
  options: StorageImageOptions,
): (src: string, size: StorageImageSize) => string | undefined {
  const storage = `${options.url.replace(/\/+$/, "")}/storage/v1`;
  const publicPrefixes = [
    `${storage}/object/public/`,
    `${storage}/render/image/public/`,
  ].map((prefix) => ({ prefix, length: new URL(prefix).pathname.length }));

  return (src, size) => {
    const prefix = publicPrefixes.find((candidate) =>
      src.startsWith(candidate.prefix),
    );
    if (prefix === undefined) return;
    const source = new URL(src);
    const object = source.pathname.slice(prefix.length);
    const target = new URL(`${storage}/render/image/public/${object}`);
    for (const [key, value] of source.searchParams)
      target.searchParams.set(key, value);
    target.searchParams.set("width", String(clamp(size.width, 1, MAX_SIDE)));
    if (size.height !== undefined) {
      target.searchParams.set(
        "height",
        String(clamp(size.height, 1, MAX_SIDE)),
      );
    }
    if (size.quality !== undefined) {
      target.searchParams.set(
        "quality",
        String(clamp(size.quality, QUALITY.min, QUALITY.max)),
      );
    }
    if (options.resize) target.searchParams.set("resize", options.resize);
    return target.toString();
  };
}
