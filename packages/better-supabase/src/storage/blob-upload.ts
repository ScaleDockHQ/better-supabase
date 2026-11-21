import type { DbError } from "../core/errors.ts";
import type { Result } from "../core/result.ts";

import { DbException, dbError, dbErrorOf } from "../core/errors.ts";
import { problemResponse } from "../core/problem.ts";

/**
 * The part of `@vercel/blob/client`'s `handleUpload` options this route uses.
 * Structural, so the package stays an optional peer the app passes in.
 */
export interface BlobHandleUploadOptions {
  readonly body: unknown;
  readonly request: Request;
  readonly onBeforeGenerateToken: (
    pathname: string,
    clientPayload: string | null,
    multipart: boolean,
  ) => Promise<{
    readonly allowedContentTypes?: string[];
    readonly maximumSizeInBytes?: number;
    readonly validUntil?: number;
    readonly addRandomSuffix?: boolean;
    readonly allowOverwrite?: boolean;
    readonly cacheControlMaxAge?: number;
    readonly ttlDays?: number;
    readonly tokenPayload?: string | null;
  }>;
  readonly onUploadCompleted?: (event: {
    readonly blob: BlobUploaded;
    readonly tokenPayload?: string | null;
  }) => Promise<void>;
  readonly token?: string;
}

/** The blob Vercel reports for a finished client upload. */
export interface BlobUploaded {
  readonly url: string;
  readonly pathname: string;
  readonly contentType: string;
  readonly contentDisposition?: string;
  readonly downloadUrl?: string;
}

export type BlobHandleUpload = (
  options: BlobHandleUploadOptions,
) => Promise<unknown>;

/** What `authorize` allows for one upload. */
export interface BlobUploadGrant {
  readonly allowedContentTypes?: readonly string[];
  readonly maximumSizeInBytes?: number;
  readonly ttlDays?: number;
  readonly addRandomSuffix?: boolean;
  /**
   * A string handed back to `onCompleted` as `tokenPayload`. Put what the
   * permission check decided in it (the tenant and folder), never trust the
   * client's own payload on completion.
   */
  readonly tokenPayload?: string;
}

export interface BlobUploadRouteOptions {
  /** `handleUpload` from `@vercel/blob/client`. */
  readonly handleUpload: BlobHandleUpload;
  /**
   * Checks the caller's permission before a token is issued: this is where your
   * own permission check runs. An error refuses the upload with that error's
   * status.
   */
  readonly authorize: (input: {
    readonly request: Request;
    readonly pathname: string;
    readonly clientPayload: string | null;
    readonly multipart: boolean;
  }) => Promise<Result<BlobUploadGrant>> | Result<BlobUploadGrant>;
  /**
   * Called when Vercel reports the finished upload, after `handleUpload`
   * verified the callback's signature. Record the attachment here. An error
   * makes the route answer 500, so Vercel retries the callback.
   */
  readonly onCompleted: (input: {
    readonly blob: BlobUploaded;
    readonly tokenPayload: string | null;
  }) => Promise<Result<unknown>> | Result<unknown>;
  readonly token?: string;
}

function fail(error: DbError): never {
  throw new DbException(error);
}

/**
 * A route handler for Vercel Blob client uploads. It answers both requests
 * `handleUpload` handles: the token request, which runs `authorize` first, and
 * the upload-completed callback, which runs `onCompleted`.
 *
 * ```ts
 * import { handleUpload } from "@vercel/blob/client";
 *
 * export const POST = blobUploadRoute({
 *   handleUpload,
 *   authorize,
 *   onCompleted,
 * });
 * ```
 */
export function blobUploadRoute(
  options: BlobUploadRouteOptions,
): (request: Request) => Promise<Response> {
  return async (request) => {
    let body: unknown;

    try {
      body = await request.json();
    } catch {
      return problemResponse(dbError("invalid_input", "Expected a JSON body"));
    }

    try {
      const json = await options.handleUpload({
        body,
        request,
        ...(options.token === undefined ? {} : { token: options.token }),
        onBeforeGenerateToken: async (
          pathname,
          clientPayload,
          multipart,
        ): Promise<
          Awaited<ReturnType<BlobHandleUploadOptions["onBeforeGenerateToken"]>>
        > => {
          const granted = await options.authorize({
            request,
            pathname,
            clientPayload,
            multipart,
          });

          if (!granted.ok) {
            return fail(granted.error);
          }

          const { allowedContentTypes, ...rest } = granted.data;

          return {
            ...rest,
            ...(allowedContentTypes === undefined
              ? {}
              : { allowedContentTypes: [...allowedContentTypes] }),
          };
        },
        onUploadCompleted: async ({ blob, tokenPayload }) => {
          const recorded = await options.onCompleted({
            blob,
            tokenPayload: tokenPayload ?? null,
          });

          if (!recorded.ok) {
            fail(recorded.error);
          }
        },
      });

      return Response.json(json);
    } catch (error) {
      return problemResponse(
        dbErrorOf(error) ??
          dbError(
            "invalid_input",
            error instanceof Error ? error.message : "Upload refused",
          ),
      );
    }
  };
}
