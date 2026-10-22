import type { NextRequest } from "next/server.js";

import { NextResponse } from "next/server.js";

import type { Aal } from "../auth/mfa.ts";
import type { AuthState } from "../auth/resolve.ts";
import type { EndedSessionOptions, RequireAalOptions } from "./types.ts";

import { checkAal } from "../auth/mfa.ts";
import { problemResponse } from "../core/problem.ts";
import { isPrefetch } from "../server/refresh.ts";

/** Response header with the URL of the request's totals on `bsb.debugRoute()`. */
export const STATS_URL_HEADER = "x-bsb-stats";

export function endedRedirect(
  request: NextRequest,
  path: string,
  reason: string,
): Response {
  const target = new URL(path, request.url);
  target.searchParams.set("reason", reason);

  return NextResponse.redirect(target);
}

export function shouldCheckSession(
  request: NextRequest,
  options: EndedSessionOptions = {},
): boolean {
  if (request.method !== "GET" && request.method !== "HEAD") {
    return false;
  }

  if (isPrefetch(request)) {
    return false;
  }

  if (request.headers.get("sec-fetch-dest") === "document") {
    return true;
  }

  return options.paths?.includes(request.nextUrl.pathname) ?? false;
}

/**
 * Page loads, client navigations and server actions; never prefetches or
 * assets.
 */
export function shouldRefresh(request: Request): boolean {
  const h = request.headers;

  if (request.method !== "GET" && request.method !== "HEAD") {
    return h.has("next-action");
  }

  if (isPrefetch(request)) {
    return false;
  }

  if (h.get("rsc") === "1") {
    return true;
  }

  const dest = h.get("sec-fetch-dest");

  if (dest) {
    return dest === "document";
  }

  return h.get("accept")?.includes("text/html") ?? false;
}

/**
 * A `proxy` `protect` that keeps signed-in users below `level` out of the
 * matched paths. The JWT carries no factor list, so this also sends users
 * without a factor to `redirect` to enroll one. Anonymous callers pass; combine
 * it with your sign-in redirect.
 *
 * ```ts
 * bsb.proxy(request, {
 *   protect: requireAal("aal2", {
 *     redirect: "/mfa",
 *     match: (path) => path.startsWith("/settings"),
 *   }),
 * });
 * ```
 */
export function requireAal(
  level: Aal,
  options: RequireAalOptions = {},
): (auth: AuthState, request: NextRequest) => Response | undefined {
  return (auth, request) => {
    const { pathname, search } = request.nextUrl;

    if (options.redirect !== undefined && pathname === options.redirect) {
      return;
    }

    if (options.match && !options.match(pathname)) {
      return;
    }

    const denied = checkAal(auth, level);

    if (!denied) {
      return;
    }

    if (options.redirect === undefined) {
      return problemResponse(denied);
    }

    const target = new URL(options.redirect, request.url);
    target.searchParams.set("next", `${pathname}${search}`);

    return NextResponse.redirect(target);
  };
}
