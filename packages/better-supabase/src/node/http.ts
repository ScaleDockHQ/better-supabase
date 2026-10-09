import type { IncomingMessage, ServerResponse } from "node:http";

import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";

import {
  applyWebHeaders,
  nodeRequestUrl,
  toWebHeaders,
} from "../bridges/node-headers.ts";

export interface WebRequestOptions {
  /**
   * Read the protocol and host from `x-forwarded-proto` and
   * `x-forwarded-host`. Turn it on behind a proxy you control. Defaults to false.
   */
  readonly trustProxy?: boolean;
  /** Stream the request body into the `Request`. Defaults to true. */
  readonly body?: boolean;
}

/**
 * A Node `IncomingMessage` as a Web `Request`. Express, Fastify and Koa
 * pass theirs (`req`, `request.raw`, `ctx.req`). With `body: false` the
 * stream stays unread, for middleware that runs before a body parser.
 */
export function toWebRequest(
  req: IncomingMessage,
  options: WebRequestOptions = {},
): Request {
  const method = req.method ?? "GET";
  const hasBody =
    (options.body ?? true) && method !== "GET" && method !== "HEAD";
  const controller = new AbortController();
  req.once("close", () => {
    if (!req.complete) controller.abort();
  });
  return new Request(nodeRequestUrl(req, options.trustProxy ?? false), {
    method,
    headers: toWebHeaders(req.headers),
    signal: controller.signal,
    ...(hasBody
      ? {
          // SAFETY: Readable.toWeb yields the bytes of the request stream.
          body: Readable.toWeb(req) as ReadableStream<Uint8Array>,
          duplex: "half",
        }
      : {}),
  });
}

/** Writes a Web `Response` to a Node `ServerResponse`, streaming the body. */
export async function sendWebResponse(
  res: ServerResponse,
  response: Response,
): Promise<void> {
  res.statusCode = response.status;
  if (response.statusText) res.statusMessage = response.statusText;
  applyWebHeaders(res, response.headers);
  if (!response.body) {
    res.end();
    return;
  }
  // SAFETY: a Response body is a byte stream, which Readable.fromWeb takes.
  const body = response.body as Parameters<typeof Readable.fromWeb>[0];
  await pipeline(Readable.fromWeb(body), res);
}
