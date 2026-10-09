import { storageImageUrl } from "../../storage/image-url.ts";

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
  readonly resize?: "cover" | "contain" | "fill";
  /**
   * For images that are not public Storage objects (local files, other
   * hosts). Defaults to returning `src` unchanged.
   */
  readonly fallback?: ImageLoader;
}

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
  const imageUrl = storageImageUrl(options);
  const fallback = options.fallback ?? (({ src }) => src);
  return (props) => imageUrl(props.src, props) ?? fallback(props);
}
