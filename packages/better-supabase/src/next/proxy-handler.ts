import type { NextRequest } from "next/server.js";

import { NextResponse } from "next/server.js";

import type { ResolvePhase } from "../auth/resolve.ts";
import type { Logger } from "../core/logger.ts";
import type { BetterServer } from "../server/server-types.ts";
import type { CollectorView } from "./collector.ts";
import type { ProxyOptions } from "./types.ts";

import { endedSessionOf } from "../auth/ended.ts";
import { outageResponse } from "../server/entries/session.ts";
import { REQUEST_ID_HEADER } from "./collector.ts";
import {
  isRedirect,
  mutableResponse,
  overrideRequestHeaders,
  serverTimingValue,
  syncMiddlewareSetCookie,
} from "./proxy.ts";
import { stampStats, verifyOption } from "./request-stats.ts";
import {
  STATS_URL_HEADER,
  endedRedirect,
  shouldCheckSession,
} from "./support.ts";

/** What the proxy needs from the server and the request's bookkeeping. */
export interface ProxyHandlerInput<C, P> {
  // oxlint-disable-next-line typescript/no-explicit-any -- the proxy reads only the session surface of any server
  readonly base: BetterServer<any, any, any, C, P, any, any>;
  readonly logger: Logger;
  readonly collector: CollectorView | undefined;
  readonly statsHeader: string;
  readonly statsRoute: string;
  readonly flushAfter: () => void;
}

/** The `proxy.ts` handler: refreshes the session and answers coarse checks. */
export function proxyHandler<C, P>(
  input: ProxyHandlerInput<C, P>,
): (
  request: NextRequest,
  proxyOptions?: ProxyOptions<C, P>,
) => Promise<Response> {
  const { base, logger, collector, statsHeader, statsRoute, flushAfter } =
    input;

  return async (request, proxyOptions = {}) => {
    const started = performance.now();
    const id = collector ? crypto.randomUUID() : undefined;
    const proxyRecorder = id ? collector?.recorderFor(id) : undefined;
    let authMs = 0;
    const phases: Partial<Record<ResolvePhase, number>> = {};

    // `before` (i18n rewrites, redirects) and auth run on the original request.
    const sessionCheck =
      proxyOptions.verifySession === true
        ? {}
        : proxyOptions.verifySession === "bootstrap"
          ? undefined
          : proxyOptions.verifySession;

    const verifySession =
      sessionCheck !== undefined && shouldCheckSession(request, sessionCheck);

    const [early, resolution] = await Promise.all([
      proxyOptions.before?.(request),
      base
        .resolve(request, {
          refresh: true,
          ...verifyOption(proxyRecorder),
          ...(verifySession ? { verifySession } : {}),
          // Under "bootstrap" the render's session check is the only one:
          // a session it found ended clears its cookies here.
          ...(proxyOptions.verifySession === "bootstrap"
            ? { endedSession: (token: string) => endedSessionOf(token) }
            : {}),
          ...(proxyOptions.leeway === undefined
            ? {}
            : { leeway: proxyOptions.leeway }),
          ...(proxyOptions.serverTiming
            ? {
                onTiming: (phase: ResolvePhase, ms: number) => {
                  phases[phase] = (phases[phase] ?? 0) + ms;
                },
              }
            : {}),
        })
        .then((resolved) => {
          authMs = performance.now() - started;

          return resolved;
        }),
    ]);

    // A refreshed token is already verified: the render reads it from the
    // memo instead of verifying it again.
    if (resolution.cookies.length > 0) {
      await base.sessions.seed(resolution.auth);
    }

    const protectMethods = proxyOptions.protectMethods;

    const runsProtect =
      protectMethods === true
        ? true
        : (protectMethods ?? ["GET", "HEAD"]).includes(request.method);

    const ended =
      resolution.sessionVerified === false &&
      sessionCheck?.redirect !== undefined &&
      request.nextUrl.pathname !== sessionCheck.redirect
        ? endedRedirect(
            request,
            sessionCheck.redirect,
            resolution.reason === "user_banned"
              ? (sessionCheck.reasons?.banned ?? "user_banned")
              : (sessionCheck.reasons?.ended ?? "session_not_found"),
          )
        : undefined;

    const custom =
      ended ??
      (await outageResponse(
        proxyOptions.onAuthOutage,
        resolution,
        request,
        logger,
      )) ??
      (runsProtect
        ? await proxyOptions.protect?.(resolution.auth, request)
        : undefined);

    const initial = custom ?? early;

    if (
      !initial &&
      resolution.cookies.length === 0 &&
      !id &&
      !proxyOptions.after &&
      !proxyOptions.serverTiming
    ) {
      flushAfter();

      return NextResponse.next();
    }

    let response = syncMiddlewareSetCookie(
      resolution.apply(mutableResponse(initial ?? NextResponse.next())),
    );

    if (!custom && !isRedirect(response)) {
      const forwarded: Record<string, string> = {};

      if (resolution.cookies.length > 0) {
        forwarded["cookie"] = resolution.requestCookies
          .map((cookie) => `${cookie.name}=${encodeURIComponent(cookie.value)}`)
          .join("; ");
      }

      if (id) {
        forwarded[REQUEST_ID_HEADER] = id;
      }

      if (Object.keys(forwarded).length > 0 || early) {
        overrideRequestHeaders(response, request, forwarded);
      }
    }

    if (id) {
      response.headers.set(REQUEST_ID_HEADER, id);
      response.headers.set(STATS_URL_HEADER, `${statsRoute}?id=${id}`);

      // Headers leave before the render runs, so this carries the proxy's own
      // verification; the render's totals come from the stats route.
      stampStats(response.headers, statsHeader, proxyRecorder);
    }

    if (proxyOptions.after) {
      const replaced = await proxyOptions.after(response, resolution.auth);

      if (replaced) {
        response = resolution.apply(mutableResponse(replaced));
      }
    }

    if (proxyOptions.serverTiming) {
      response.headers.append(
        "server-timing",
        serverTimingValue({
          "bsb-proxy": performance.now() - started,
          "bsb-auth": authMs,
          ...Object.fromEntries(
            Object.entries(phases).map(([phase, ms]) => [`bsb-${phase}`, ms]),
          ),
        }),
      );
    }

    // A refresh or sign-out in `resolve`, or `protect`, can start sink sends.
    flushAfter();

    return response;
  };
}
