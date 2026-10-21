/** Storage's image transformation limits. */
export const MAX_SIDE = 2500;
export const QUALITY = { min: 20, max: 100 } as const;

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

const clamp = (value: number, min: number, max: number): number =>
  Math.min(max, Math.max(min, Math.round(value)));

const positive = (value: string | null): number | undefined => {
  const parsed = Number(value);

  return value !== null && Number.isFinite(parsed) && parsed > 0
    ? parsed
    : undefined;
};

/**
 * Turns public Storage object URLs into Supabase image transformation URLs
 * (`/render/image/public`) at a given size. Any other URL (local files, other
 * hosts, signed URLs) comes back as `undefined`: a signed URL's token covers
 * the transform it was signed with, so sign it with `renderUrl()`.
 *
 * A crop keeps its shape: when `size` has no `height` but `src` already carries
 * a `width` and `height` (a render URL from a variant), the height scales with
 * the new width. Both sides stop at Storage's 2500 limit by the same factor.
 *
 * ```ts
 * const imageUrl = storageImageUrl({ url: SUPABASE_URL });
 * imageUrl(avatar, { width: 96 }) ?? avatar;
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

    if (prefix === undefined) {
      return;
    }

    const source = new URL(src);
    const object = source.pathname.slice(prefix.length);
    const target = new URL(`${storage}/render/image/public/${object}`);

    for (const [key, value] of source.searchParams) {
      target.searchParams.set(key, value);
    }

    const sourceWidth = positive(source.searchParams.get("width"));
    const sourceHeight = positive(source.searchParams.get("height"));

    const height =
      size.height ??
      (sourceWidth !== undefined && sourceHeight !== undefined
        ? (size.width * sourceHeight) / sourceWidth
        : undefined);

    const factor = Math.min(
      1,
      MAX_SIDE / size.width,
      height === undefined ? 1 : MAX_SIDE / height,
    );

    target.searchParams.set(
      "width",
      String(clamp(size.width * factor, 1, MAX_SIDE)),
    );

    if (height !== undefined) {
      target.searchParams.set(
        "height",
        String(clamp(height * factor, 1, MAX_SIDE)),
      );
    }

    if (size.quality !== undefined) {
      target.searchParams.set(
        "quality",
        String(clamp(size.quality, QUALITY.min, QUALITY.max)),
      );
    }

    if (options.resize) {
      target.searchParams.set("resize", options.resize);
    }

    return target.toString();
  };
}

/**
 * Builds a `srcset` of public Storage images at `densities` times the size
 * (`1x` and `2x` by default) for a plain `<img>`. Returns `undefined` for the
 * URLs `storageImageUrl` leaves alone.
 *
 * ```tsx
 * const srcSet = storageImageSrcSet({ url: SUPABASE_URL });
 * <img
 *   src={avatar}
 *   srcSet={srcSet(avatar, { width: 96, height: 96 })}
 *   width={96}
 *   height={96}
 * />;
 * ```
 */
export function storageImageSrcSet(
  options: StorageImageOptions,
): (
  src: string,
  size: StorageImageSize,
  densities?: readonly number[],
) => string | undefined {
  const imageUrl = storageImageUrl(options);

  return (src, size, densities = [1, 2]) => {
    const entries: string[] = [];

    for (const density of densities) {
      const url = imageUrl(src, {
        width: size.width * density,
        height: size.height === undefined ? undefined : size.height * density,
        quality: size.quality,
      });

      if (url === undefined) {
        return;
      }

      entries.push(`${url} ${String(density)}x`);
    }

    return entries.join(", ");
  };
}
