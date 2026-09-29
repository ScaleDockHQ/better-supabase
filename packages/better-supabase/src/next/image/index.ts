/** What `next/image` passes to a custom loader. */
export interface ImageLoaderProps {
  readonly src: string;
  readonly width: number;
  readonly quality?: number;
}

export type ImageLoader = (props: ImageLoaderProps) => string;

export interface ImageLoaderOptions {
  /** Project URL, e.g. `process.env.NEXT_PUBLIC_SUPABASE_URL`. */
  readonly url: string;
  /** Resize mode for the transform. Defaults to Storage's own (`cover`). */
  readonly resize?: 'cover' | 'contain' | 'fill';
  /**
   * For images that are not public Storage objects (local files, other
   * hosts). Defaults to returning `src` unchanged.
   */
  readonly fallback?: ImageLoader;
}

/** Storage's image transformation limits. */
const MAX_WIDTH = 2500;
const QUALITY = { min: 20, max: 100 } as const;

const clamp = (value: number, min: number, max: number): number =>
  Math.min(max, Math.max(min, Math.round(value)));

/**
 * A `next/image` loader that serves public Storage objects through
 * Supabase image transformations (`/render/image/public`), so Next.js does
 * not proxy or re-encode them:
 *
 * ```ts
 * // src/image-loader.ts, set as `images.loaderFile` in next.config.ts
 * export default createImageLoader({ url: process.env.NEXT_PUBLIC_SUPABASE_URL! });
 * ```
 *
 * Signed URLs pass through unchanged: their token covers the transform they
 * were signed with, so sign them with `renderUrl()` at the size you render.
 */
export function createImageLoader(options: ImageLoaderOptions): ImageLoader {
  const storage = `${options.url.replace(/\/+$/, '')}/storage/v1`;
  const publicPrefixes = [
    `${storage}/object/public/`,
    `${storage}/render/image/public/`,
  ];
  const fallback = options.fallback ?? (({ src }) => src);

  return (props) => {
    const prefix = publicPrefixes.find((candidate) =>
      props.src.startsWith(candidate),
    );
    if (prefix === undefined) return fallback(props);
    const source = new URL(props.src);
    const object = source.pathname.slice(new URL(prefix).pathname.length);
    const target = new URL(`${storage}/render/image/public/${object}`);
    for (const [key, value] of source.searchParams)
      target.searchParams.set(key, value);
    target.searchParams.set('width', String(clamp(props.width, 1, MAX_WIDTH)));
    if (props.quality !== undefined) {
      target.searchParams.set(
        'quality',
        String(clamp(props.quality, QUALITY.min, QUALITY.max)),
      );
    }
    if (options.resize) target.searchParams.set('resize', options.resize);
    return target.toString();
  };
}
