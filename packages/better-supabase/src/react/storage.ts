"use client";

import { useEffect, useMemo, useRef, useState } from "react";

import type { DbError } from "../core/errors.ts";
import type { AsyncResult, Result } from "../core/result.ts";
import type {
  ImageTransform,
  TransformOptions,
  UploadBody,
  UploadOptions,
  UrlOptions,
} from "../storage/bucket.ts";
import type { TtlPreset } from "../storage/ttl.ts";

import { err, ok, toDbError } from "../core/result.ts";
import { ttlSeconds } from "../storage/ttl.ts";
import { scaleTransform, transformFor } from "../storage/variants.ts";

/** The part of a connected bucket `useSignedUrl` calls. */
export interface SignedUrlSource<T> {
  signedUrl(target: T, options?: UrlOptions): AsyncResult<string>;
}

export interface SignedUrl {
  /** `undefined` until the first URL arrives, and while paused. */
  readonly url: string | undefined;
  readonly error: DbError | undefined;
  readonly loading: boolean;
}

/** Re-sign this share of the TTL before the URL expires. */
const REFRESH_AT = 0.9;

/**
 * A signed URL for an object, signed again before it expires. Pass `null` as
 * the target to pause. Connect the bucket with `cacheSignedUrls: true` so
 * components showing the same object share one URL.
 *
 * ```tsx
 * const { url } = useSignedUrl(
 *   avatars,
 *   user ? { userId: user.id } : null,
 *   { ttl: "hour" },
 * );
 * ```
 */
export function useSignedUrl<T>(
  bucket: SignedUrlSource<T>,
  target: T | null | undefined,
  options: UrlOptions = {},
): SignedUrl {
  const key =
    target === null || target === undefined
      ? null
      : JSON.stringify([target, options]);

  const [state, setState] = useState<{
    readonly key: string | null;
    readonly url: string | undefined;
    readonly error: DbError | undefined;
  }>({ key: null, url: undefined, error: undefined });

  const latest = useRef({ target, options });
  // oxlint-disable-next-line react/refs -- latest-ref pattern; the react peer range predates useEffectEvent.
  latest.current = { target, options };
  const ttl = ttlSeconds(options.ttl);

  useEffect(() => {
    if (key === null) {
      return;
    }

    let active = true;

    const sign = () => {
      const current = latest.current.target;

      if (current === null || current === undefined) {
        return;
      }

      void bucket.signedUrl(current, latest.current.options).then((result) => {
        if (!active) {
          return result;
        }

        if (!result.ok) {
          setState((last) => ({
            key,
            url: last.key === key ? last.url : undefined,
            error: result.error,
          }));

          return result;
        }

        setState({ key, url: result.data, error: undefined });

        return result;
      });
    };

    sign();
    const timer = setInterval(sign, ttl * 1000 * REFRESH_AT);

    return () => {
      active = false;
      clearInterval(timer);
    };
  }, [bucket, key, ttl]);

  const fresh = key !== null && state.key === key;

  return {
    url: fresh ? state.url : undefined,
    error: fresh ? state.error : undefined,
    loading:
      key !== null && (!fresh || (state.url === undefined && !state.error)),
  };
}

/** The part of a connected bucket `useImage` calls. */
export interface ImageSource<T, V extends string = never> {
  readonly bucket: {
    readonly id: string;
    readonly public: boolean;
    readonly variants: Readonly<Record<V, TransformOptions>>;
  };
  publicUrl(
    target: T,
    options?: {
      readonly transform?: TransformOptions;
      readonly cacheNonce?: string;
    },
  ): Result<string>;
  signedUrl(target: T, options?: UrlOptions): AsyncResult<string>;
}

export interface UseImageOptions {
  /** Pixel densities for `srcSet`. Defaults to `[1, 2]`. */
  readonly densities?: readonly number[];
  /** How long signed URLs of a private bucket last. Defaults to `hour`. */
  readonly ttl?: number | TtlPreset;
  /** Added to the URLs so browsers fetch a replaced object again. */
  readonly cacheNonce?: string;
}

export interface StorageImage {
  /** The URL at the first density; `undefined` while loading or paused. */
  readonly src: string | undefined;
  /** `url 1x, url 2x`; `undefined` while loading, paused, or for one density. */
  readonly srcSet: string | undefined;
  /** The transform's width and height, for the `<img>` attributes. */
  readonly width: number | undefined;
  readonly height: number | undefined;
  readonly error: DbError | undefined;
  readonly loading: boolean;
}

const DENSITIES = [1, 2];

const IDLE_IMAGE: StorageImage = {
  src: undefined,
  srcSet: undefined,
  width: undefined,
  height: undefined,
  error: undefined,
  loading: false,
};

/**
 * The `src` and `srcSet` of a stored image at a variant or transform. Public
 * buckets build the URLs during render, with no request. Private buckets sign
 * one URL per density and sign them again before they expire, since a signed
 * URL's token covers the size it was signed at. Pass `null` as the target to
 * pause.
 *
 * ```tsx
 * const avatar = useImage(
 *   avatars,
 *   user ? { userId: user.id, version, ext } : null,
 *   "md",
 * );
 * <img
 *   src={avatar.src}
 *   srcSet={avatar.srcSet}
 *   width={avatar.width}
 *   height={avatar.height}
 *   alt=""
 * />;
 * ```
 */
export function useImage<T, V extends string = never>(
  source: ImageSource<T, V>,
  target: T | null | undefined,
  transform: ImageTransform<V>,
  options: UseImageOptions = {},
): StorageImage {
  const { bucket } = source;
  const given = [...new Set(options.densities ?? DENSITIES)];
  const densities = given.length > 0 ? given : [1];
  const ttl = ttlSeconds(options.ttl);
  const { cacheNonce } = options;

  const resolved = ((): Result<TransformOptions> => {
    try {
      return ok(transformFor(bucket.id, bucket.variants, transform) ?? {});
    } catch (cause) {
      return err(toDbError(cause));
    }
  })();

  const scaled = resolved.ok
    ? densities.map((density) => scaleTransform(resolved.data, density))
    : [];

  const key =
    target === null || target === undefined || !resolved.ok
      ? null
      : JSON.stringify([target, scaled, ttl, cacheNonce]);

  const [state, setState] = useState<{
    readonly key: string | null;
    readonly urls: readonly string[] | undefined;
    readonly error: DbError | undefined;
  }>({ key: null, urls: undefined, error: undefined });

  const latest = useRef({ target, scaled, cacheNonce });
  // oxlint-disable-next-line react/refs -- latest-ref pattern; the react peer range predates useEffectEvent.
  latest.current = { target, scaled, cacheNonce };

  const isPublic = bucket.public;

  useEffect(() => {
    if (key === null || isPublic) {
      return;
    }

    let active = true;

    const sign = () => {
      const current = latest.current;
      const currentTarget = current.target;

      if (currentTarget === null || currentTarget === undefined) {
        return;
      }

      const signing = current.scaled.map(async (transformAt) =>
        source.signedUrl(currentTarget, {
          ttl,
          transform: transformAt,
          ...(current.cacheNonce ? { cacheNonce: current.cacheNonce } : {}),
        }),
      );

      void Promise.all(signing).then((results) => {
        if (!active) {
          return results;
        }

        const urls: string[] = [];

        for (const result of results) {
          if (!result.ok) {
            setState((last) => ({
              key,
              urls: last.key === key ? last.urls : undefined,
              error: result.error,
            }));

            return results;
          }

          urls.push(result.data);
        }

        setState({ key, urls, error: undefined });

        return results;
      });
    };

    sign();
    const timer = setInterval(sign, ttl * 1000 * REFRESH_AT);

    return () => {
      active = false;
      clearInterval(timer);
    };
  }, [source, isPublic, key, ttl, latest]);

  if (!resolved.ok) {
    return { ...IDLE_IMAGE, error: resolved.error };
  }

  const size = { width: resolved.data.width, height: resolved.data.height };

  if (key === null || target === null || target === undefined) {
    return { ...IDLE_IMAGE, ...size };
  }

  if (bucket.public) {
    return {
      ...publicImage(source, target, scaled, densities, cacheNonce),
      ...size,
    };
  }

  const fresh = state.key === key;
  const urls = fresh ? state.urls : undefined;

  return {
    ...urlsToImage(urls, densities),
    ...size,
    error: fresh ? state.error : undefined,
    loading: !fresh || (urls === undefined && !state.error),
  };
}

function urlsToImage(
  urls: readonly string[] | undefined,
  densities: readonly number[],
): Pick<StorageImage, "src" | "srcSet"> {
  if (urls === undefined || urls.length === 0) {
    return { src: undefined, srcSet: undefined };
  }

  return {
    src: urls[0],
    srcSet:
      urls.length > 1
        ? urls
            .map((url, index) => `${url} ${String(densities[index])}x`)
            .join(", ")
        : undefined,
  };
}

function publicImage<T, V extends string>(
  source: ImageSource<T, V>,
  target: T,
  scaled: readonly TransformOptions[],
  densities: readonly number[],
  cacheNonce: string | undefined,
): Pick<StorageImage, "src" | "srcSet" | "error" | "loading"> {
  const urls: string[] = [];

  for (const transformAt of scaled) {
    const url = source.publicUrl(target, {
      transform: transformAt,
      ...(cacheNonce ? { cacheNonce } : {}),
    });

    if (!url.ok) {
      return { ...IDLE_IMAGE, error: url.error };
    }

    urls.push(url.data);
  }

  return { ...urlsToImage(urls, densities), error: undefined, loading: false };
}

/** The part of a connected bucket `useUpload` calls. */
export interface UploadTarget<T, R> {
  upload(target: T, body: UploadBody, options?: UploadOptions): AsyncResult<R>;
}

export type UploadStatus = "idle" | "uploading" | "done" | "error";

export interface Upload<T, R> {
  readonly status: UploadStatus;
  /**
   * 0 to 1 while uploading; see `UploadOptions.onProgress` for when it is
   * exact.
   */
  readonly progress: number;
  readonly data: R | undefined;
  readonly error: DbError | undefined;
  /** Starts an upload; a new one aborts the one in flight. */
  readonly upload: (
    target: T,
    body: UploadBody,
    options?: Omit<UploadOptions, "signal" | "onProgress">,
  ) => Promise<Result<R>>;
  /** Cancels the upload in flight. */
  readonly abort: () => void;
  /** Back to `idle`. */
  readonly reset: () => void;
}

export interface UseUploadOptions<R> {
  readonly onSuccess?: (data: R) => void;
  readonly onError?: (error: DbError) => void;
}

interface UploadState<R> {
  readonly status: UploadStatus;
  readonly progress: number;
  readonly data: R | undefined;
  readonly error: DbError | undefined;
}

const IDLE: UploadState<never> = {
  status: "idle",
  progress: 0,
  data: undefined,
  error: undefined,
};

/**
 * Uploads to a connected bucket with progress, abort and status state.
 * Unmounting aborts the upload in flight.
 *
 * ```tsx
 * const avatar = useUpload(avatars, { onSuccess: ({ path }) => save(path) });
 * <input type="file" onChange={(e) => avatar.upload({ userId }, e.target.files[0], { upsert: true })} />
 * <progress value={avatar.progress} />
 * ```
 */
export function useUpload<T, R>(
  bucket: UploadTarget<T, R>,
  options: UseUploadOptions<R> = {},
): Upload<T, R> {
  const [state, setState] = useState<UploadState<R>>(IDLE);

  const latest = useRef<{
    controller: AbortController | undefined;
    options: UseUploadOptions<R>;
  }>({ controller: undefined, options });

  // oxlint-disable-next-line react/refs -- latest-ref pattern; the react peer range predates useEffectEvent.
  latest.current.options = options;

  useEffect(
    () => () => {
      latest.current.controller?.abort();
    },
    [],
  );

  const calls = useMemo(() => {
    const stop = () => {
      latest.current.controller?.abort();
      latest.current.controller = undefined;
      setState(IDLE);
    };

    return {
      upload: async (
        target: T,
        body: UploadBody,
        uploadOptions?: Omit<UploadOptions, "signal" | "onProgress">,
      ): Promise<Result<R>> => {
        latest.current.controller?.abort();
        const controller = new AbortController();
        latest.current.controller = controller;
        const mine = () => latest.current.controller === controller;
        setState({ ...IDLE, status: "uploading" });
        let result: Result<R>;

        try {
          result = await bucket.upload(target, body, {
            ...uploadOptions,
            signal: controller.signal,
            onProgress: (progress) => {
              if (mine()) {
                setState((last) => ({ ...last, progress }));
              }
            },
          });
        } catch (cause) {
          result = err(toDbError(cause));
        }

        if (!mine() || controller.signal.aborted) {
          return result;
        }

        latest.current.controller = undefined;

        if (result.ok) {
          setState({
            status: "done",
            progress: 1,
            data: result.data,
            error: undefined,
          });
          latest.current.options.onSuccess?.(result.data);
        } else {
          setState((last) => ({
            ...last,
            status: "error",
            error: result.error,
          }));
          latest.current.options.onError?.(result.error);
        }

        return result;
      },
      abort: stop,
      reset: stop,
    };
  }, [bucket]);

  return { ...state, ...calls };
}
