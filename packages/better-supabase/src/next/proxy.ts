import { NextResponse } from "next/server.js";

const OVERRIDE = "x-middleware-override-headers";
const REQUEST_PREFIX = "x-middleware-request-";

/** A response whose headers can be changed (`Response.redirect()`'s cannot). */
export function mutableResponse(response: Response): Response {
  try {
    response.headers.append("x-bs-probe", "1");
    response.headers.delete("x-bs-probe");
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
    for (const [name, value] of request.headers) current.set(name, value);
  } else {
    for (const name of listed.split(",")) {
      const value = response.headers.get(`${REQUEST_PREFIX}${name.trim()}`);
      if (name.trim() && value !== null) current.set(name.trim(), value);
    }
  }
  for (const [name, value] of Object.entries(set)) current.set(name, value);
  for (const name of [...response.headers.keys()]) {
    if (name.startsWith(REQUEST_PREFIX)) response.headers.delete(name);
  }
  response.headers.set(OVERRIDE, [...current.keys()].join(","));
  for (const [name, value] of current) {
    response.headers.set(`${REQUEST_PREFIX}${name}`, value);
  }
}

/** `bs-proxy;dur=1.2, bs-verify;dur=0.4`, per W3C Server Timing. */
export function serverTimingValue(
  metrics: Readonly<Record<string, number>>,
): string {
  return Object.entries(metrics)
    .map(([name, ms]) => `${name};dur=${ms.toFixed(1)}`)
    .join(", ");
}
