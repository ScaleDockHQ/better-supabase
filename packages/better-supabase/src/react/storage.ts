"use client";

import { useEffect, useMemo, useRef, useState } from "react";

import type { DbError } from "../core/errors.ts";
import type { AsyncResult, Result } from "../core/result.ts";
import type {
  UploadBody,
  UploadOptions,
  UrlOptions,
} from "../storage/bucket.ts";

import { err, toDbError } from "../core/result.ts";
import { ttlSeconds } from "../storage/ttl.ts";

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
 * A signed URL for an object, signed again before it expires. Pass `null`
 * as the target to pause. Connect the bucket with `cacheSignedUrls: true`
 * so components showing the same object share one URL.
 *
 * ```tsx
 * const { url } = useSignedUrl(avatars, user ? { userId: user.id } : null, { ttl: 'hour' });
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
    if (key === null) return;
    let active = true;
    const sign = () => {
      const current = latest.current.target;
      if (current === null || current === undefined) return;
      void bucket.signedUrl(current, latest.current.options).then((result) => {
        if (!active) return;
        if (!result.ok) {
          setState((last) => ({
            key,
            url: last.key === key ? last.url : undefined,
            error: result.error,
          }));
          return;
        }
        setState({ key, url: result.data, error: undefined });
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

/** The part of a connected bucket `useUpload` calls. */
export interface UploadTarget<T, R> {
  upload(target: T, body: UploadBody, options?: UploadOptions): AsyncResult<R>;
}

export type UploadStatus = "idle" | "uploading" | "done" | "error";

export interface Upload<T, R> {
  readonly status: UploadStatus;
  /** 0 to 1 while uploading; see `UploadOptions.onProgress` for when it is exact. */
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
              if (mine()) setState((last) => ({ ...last, progress }));
            },
          });
        } catch (cause) {
          result = err(toDbError(cause));
        }
        if (!mine() || controller.signal.aborted) return result;
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
