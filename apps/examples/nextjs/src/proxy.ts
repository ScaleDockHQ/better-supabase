import type { ProxyOptions } from "better-supabase/next";
import type { NextRequest } from "next/server";

import { permissionMatches } from "better-supabase/blocks/permissions";
import { permissionsOf, toSession } from "better-supabase/next";
import { precompute } from "flags/next";
import { hasLocale } from "next-intl";
import createMiddleware from "next-intl/middleware";
import { NextResponse } from "next/server";

import { env } from "@/env";

import { requiredPermission } from "./features/navigation/nav-items";
import { pricingFlags } from "./flags";
import { routing } from "./i18n/routing";
import { bsb } from "./lib/supabase/server";

const intl = createMiddleware(routing);

/** Pages a signed-out visitor may open; the rest redirect to sign-in. */
const PUBLIC = new Set([
  "/login",
  "/signup",
  "/forgot-password",
  "/reset-password",
  "/waitlist",
]);

/** Pages a signed-in user skips straight to the dashboard from. */
const GUEST_ONLY = new Set(["/login", "/signup", "/forgot-password"]);

function splitLocale(pathname: string) {
  const [, locale, ...rest] = pathname.split("/");

  if (!hasLocale(routing.locales, locale)) {
    return null;
  }

  return { locale, path: `/${rest.join("/")}`.replace(/\/$/, "") || "/" };
}

/**
 * Optimistic redirects from the (locally verified) token. Pages, actions and
 * RLS still check; this only saves rendering a page the user can't use. A path
 * without a locale is left to next-intl's redirect. A page whose menu entry
 * needs a key the token's `permissions` claim lacks rewrites to the 403 page;
 * without the claim (or with it truncated) the page decides.
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
    path.startsWith("/status/");

  if (session.kind !== "user") {
    if (isPublic) {
      return;
    }

    const login = new URL(`/${locale}/login`, request.url);
    login.searchParams.set("next", `${pathname}${search}`);

    return NextResponse.redirect(login);
  }

  if (GUEST_ONLY.has(path)) {
    return NextResponse.redirect(new URL(`/${locale}`, request.url));
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

export const proxy = (request: NextRequest) =>
  bsb.proxy(request, {
    // Adds the locale prefix (Accept-Language, then the NEXT_LOCALE cookie).
    before: (req) =>
      req.nextUrl.pathname.startsWith("/api/") ? undefined : intl(req),
    protect,
    // Prefetches never refresh; an expired token prefetches the page signed out.
    onExpiredPrefetch: "render",
    after: (response, auth) => {
      // Shared caches must never store a signed-in response.
      if (auth.kind === "user") {
        response.headers.append("vary", "cookie");
      }
    },
    // The phases show whether a page load called Auth.
    serverTiming:
      env.NODE_ENV !== "production" || env.EXPOSE_TESTING_API === "1",
  });

export const config = {
  matcher: [
    // The workflow, Flags Explorer and MCP metadata routes answer without a
    // session; the proxy would redirect them to a locale or the sign-in page.
    "/((?!_next/static|_next/image|favicon.ico|\\.well-known/workflow/|\\.well-known/vercel/|\\.well-known/oauth-protected-resource|.*\\.(?:svg|png|jpg|webp|ico|txt|js|html|webmanifest)$).*)",
  ],
};
