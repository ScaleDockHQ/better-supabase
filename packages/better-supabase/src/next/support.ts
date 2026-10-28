import type { NextRequest } from "next/server.js";

import { NextResponse } from "next/server.js";

import type { Aal } from "../auth/mfa.ts";
import type { AuthState } from "../auth/resolve.ts";
import type { VerifySessionOptions, RequireAalOptions } from "./types.ts";

import { checkAal } from "../auth/mfa.ts";
import { problemResponse } from "../core/problem.ts";
import { isDocumentLoad } from "../server/request-kind.ts";

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

/**
 * Whether the proxy asks Auth if the session still exists: top-level document
 * loads (`sec-fetch-dest: document`) on `options.paths`, else on every path.
 * Next.js strips its router headers before the proxy runs, so client
 * navigations and prefetches are told apart by the browser's own headers.
 */
export function shouldCheckSession(
  request: NextRequest,
  options: VerifySessionOptions = {},
): boolean {
  if (!isDocumentLoad(request)) {
    return false;
  }

  return options.paths?.includes(request.nextUrl.pathname) ?? true;
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
