import type { ProxyOptions } from "better-supabase/next";
import type { NextRequest } from "next/server";

import { permissionMatches } from "better-supabase/blocks/permissions";
import {
  createProxy,
  permissionsOf,
  postAuthPath,
  toSession,
} from "better-supabase/next/proxy";
import { precompute } from "flags/next";
import { hasLocale } from "next-intl";
import createMiddleware from "next-intl/middleware";
import { NextResponse } from "next/server";

import { env } from "@/env";

import { requiredPermission } from "./features/navigation/nav-items";
import { pricingFlags, signupWaitlist, VISITOR_COOKIE } from "./flags";
import { localizedPath, routing } from "./i18n/routing";
import { app } from "./lib/supabase/app";

const intl = createMiddleware(routing);

// A rewrite names the internal `/[locale]/...` route, which always has the
// segment; a redirect is a URL the visitor sees, so it goes through `localizedPath`.

/** Pages a signed-out visitor may open; the rest redirect to sign-in. */
const PUBLIC = new Set([
  "/login",
  "/signup",
  "/forgot-password",
  "/reset-password",
  "/waitlist",
]);

/** Pages a signed-in user skips, to the `?next=` path or the dashboard. */
const GUEST_ONLY = new Set(["/login", "/signup", "/forgot-password"]);

/**
 * The locale and the path inside it. With `localePrefix: "as-needed"` a path
 * without a prefix is a page of the default locale, so it is protected like any
 * other.
 */
function splitLocale(pathname: string) {
  const [, first, ...rest] = pathname.split("/");

  if (!hasLocale(routing.locales, first)) {
    return {
      locale: routing.defaultLocale,
      path: pathname.replace(/\/$/, "") || "/",
    };
  }

  return {
    locale: first,
    path: `/${rest.join("/")}`.replace(/\/$/, "") || "/",
  };
}

/**
 * Optimistic redirects from the (locally verified) token. Pages, actions and
 * RLS still check; this only saves rendering a page the user can't use. A page
 * whose menu entry needs a key the token's `permissions` claim lacks rewrites
 * to the 403 page; without the claim (or with it truncated) the page decides.
 */
const protect: NonNullable<ProxyOptions["protect"]> = async (auth, request) => {
  // A Server Action posts to the page it runs on; redirecting it drops the action.
  if (request.method !== "GET" && request.method !== "HEAD") {
    return;
  }

  const { pathname, search } = request.nextUrl;
  const route = pathname.startsWith("/api/") ? null : splitLocale(pathname);

  if (!route) {
    return;
  }

  const { locale, path } = route;

  // The pricing flags are evaluated here once, and the static page for
  // their values is served; `precompute` signs them with FLAGS_SECRET.
  if (path === "/pricing") {
    const code = env.FLAGS_SECRET ? await precompute(pricingFlags) : "default";

    return NextResponse.rewrite(
      new URL(`/${locale}/pricing/${code}${search}`, request.url),
    );
  }

  const session = toSession(auth);

  const isPublic =
    PUBLIC.has(path) ||
    path.startsWith("/invite/") ||
    path.startsWith("/pricing/") ||
    path.startsWith("/share/") ||
    path.startsWith("/book/") ||
    path.startsWith("/send/") ||
    path.startsWith("/status/") ||
    path.startsWith("/store/");

  if (session.kind !== "user") {
    if (path === "/signup" && (await signupWaitlist())) {
      return NextResponse.rewrite(
        new URL(`/${locale}/waitlist${search}`, request.url),
      );
    }

    if (isPublic) {
      return;
    }

    const login = new URL(localizedPath(locale, "/login"), request.url);
    login.searchParams.set("next", `${pathname}${search}`);

    return NextResponse.redirect(login);
  }

  // A signed-in user who opens the sign-in page goes where `?next=` points.
  if (GUEST_ONLY.has(path)) {
    return NextResponse.redirect(
      new URL(postAuthPath(request, localizedPath(locale, "/")), request.url),
    );
  }

  const needed = requiredPermission(path);
  const keys = permissionsOf(session);

  if (
    needed !== undefined &&
    keys !== undefined &&
    !keys.some((granted) => permissionMatches(granted, needed))
  ) {
    return NextResponse.rewrite(
      new URL(`/${locale}/forbidden${search}`, request.url),
    );
  }

  return;
};

// The proxy builds only the session runtime from the app definition, so it
// loads neither the block set nor the data layer (ADR 0635).
const handle = createProxy(app, {
  debug: {
    enabled: env.EXPOSE_TESTING_API === "1",
    budget: { calls: 8, waves: 2 },
    route: "/api/bs-stats",
  },
  // Adds the locale prefix (Accept-Language, then the NEXT_LOCALE cookie).
  before: (req) =>
    req.nextUrl.pathname.startsWith("/api/") ? undefined : intl(req),
  protect,
  after: (response, auth, request) => {
    // Shared caches must never store a signed-in response.
    if (auth.kind === "user") {
      response.headers.append("vary", "cookie");
    }

    // The first request has no visitor id yet, so its rollouts use the
    // organization; every later request keeps one bucket.
    // next-intl's response writes its cookies through `response.cookies`,
    // which drops a `set-cookie` header appended beside it.
    if (
      !request.cookies.has(VISITOR_COOKIE) &&
      response instanceof NextResponse
    ) {
      response.cookies.set(VISITOR_COOKIE, crypto.randomUUID(), {
        path: "/",
        maxAge: 60 * 60 * 24 * 365,
        sameSite: "lax",
        httpOnly: true,
        secure: true,
      });
    }
  },
  // The phases show whether a page load called Auth.
  serverTiming: env.NODE_ENV !== "production" || env.EXPOSE_TESTING_API === "1",
});

export const proxy = (request: NextRequest) => handle(request);

export const config = {
  matcher: [
    // The workflow, Flags Explorer and MCP metadata routes answer without a
    // session; the proxy would redirect them to a locale or the sign-in page.
    "/((?!_next/static|_next/image|favicon.ico|\\.well-known/workflow/|\\.well-known/vercel/|\\.well-known/oauth-protected-resource|.*\\.(?:svg|png|jpg|webp|ico|txt|js|html|webmanifest)$).*)",
  ],
};
