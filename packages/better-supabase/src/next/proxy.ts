import { NextResponse } from "next/server.js";

const OVERRIDE = "x-middleware-override-headers";
const REQUEST_PREFIX = "x-middleware-request-";
const SET_COOKIE = "x-middleware-set-cookie";
const MAX_AGE_ZERO = /;\s*max-age=0\s*(?:;|$)/i;
const HAS_EXPIRES = /;\s*expires=/i;

/** A response whose headers can be changed (`Response.redirect()`'s cannot). */
export function mutableResponse(response: Response): Response {
  try {
    response.headers.append("x-bsb-probe", "1");
    response.headers.delete("x-bsb-probe");

    return response;
  } catch {
    return new NextResponse(response.body, {
      status: response.status,
      statusText: response.statusText,
      headers: new Headers(response.headers),
    });
  }
}

export const isRedirect = (response: Response): boolean =>
  response.status >= 300 &&
  response.status < 400 &&
  response.headers.has("location");

/**
 * Sets request headers the rest of the request sees, the way
 * `NextResponse.next({ request: { headers } })` does, on a response that may
 * already override some (next-intl sets its locale this way). Next.js keeps
 * only the headers listed in `x-middleware-override-headers`, so the full set
 * is written back.
 */
export function overrideRequestHeaders(
  response: Response,
  request: Request,
  set: Readonly<Record<string, string>>,
): void {
  const listed = response.headers.get(OVERRIDE);
  const current = new Headers();

  if (listed === null) {
    for (const [name, value] of request.headers) {
      current.set(name, value);
    }
  } else {
    for (const name of listed.split(",")) {
      const value = response.headers.get(`${REQUEST_PREFIX}${name.trim()}`);

      if (name.trim() && value !== null) {
        current.set(name.trim(), value);
      }
    }
  }

  for (const [name, value] of Object.entries(set)) {
    current.set(name, value);
  }

  for (const name of [...response.headers.keys()]) {
    if (name.startsWith(REQUEST_PREFIX)) {
      response.headers.delete(name);
    }
  }

  response.headers.set(OVERRIDE, [...current.keys()].join(","));

  for (const [name, value] of current) {
    response.headers.set(`${REQUEST_PREFIX}${name}`, value);
  }
}

/** `bsb-proxy;dur=1.2, bsb-verify;dur=0.4`, per W3C Server Timing. */
export function serverTimingValue(
  metrics: Readonly<Record<string, number>>,
): string {
  return Object.entries(metrics)
    .map(([name, ms]) => `${name};dur=${ms.toFixed(1)}`)
    .join(", ");
}

/**
 * Copies the response's `set-cookie` headers into `x-middleware-set-cookie`,
 * which Next.js merges into the render's `cookies()`, so the page that follows
 * a refresh reads the new token. A `NextResponse` whose cookies a `before` hook
 * set carries the header already, without the proxy's cookies. A cookie cleared
 * with only `Max-Age=0` gets an `Expires` in the past, which the render reads
 * as deleted.
 */
export function syncMiddlewareSetCookie(response: Response): Response {
  const cookies = response.headers.getSetCookie();

  if (cookies.length === 0) {
    return response;
  }

  response.headers.set(
    SET_COOKIE,
    cookies
      .map((cookie) =>
        MAX_AGE_ZERO.test(cookie) && !HAS_EXPIRES.test(cookie)
          ? `${cookie}; Expires=Thu, 01 Jan 1970 00:00:00 GMT`
          : cookie,
      )
      .join(","),
  );

  return response;
}
