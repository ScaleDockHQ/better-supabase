import type { NextRequest } from "next/server";

import { isMarkdownPreferred } from "fumadocs-core/negotiation";
import { NextResponse } from "next/server";

import { docsPathSlug } from "./lib/page-slugs";
import slugs from "./lib/page-slugs.json" with { type: "json" };
import { docsContentRoute } from "./lib/shared";

const pageSlugs: ReadonlySet<string> = new Set(slugs);

/** No route matches it, so Next renders `app/global-not-found.tsx` with a 404. */
const NOT_FOUND_PATH = "/_not-found-docs";

/**
 * Unknown docs URLs answer 404 instead of a streamed 200 (`notFound()` inside
 * Suspense can't change the status), and a client that asks for Markdown
 * (`Accept: text/markdown`) gets the page's `.md` form.
 */
export function proxy(request: NextRequest): NextResponse {
  const slug = docsPathSlug(request.nextUrl.pathname);
  if (slug === undefined) return NextResponse.next();

  if (!pageSlugs.has(slug)) {
    return NextResponse.rewrite(new URL(NOT_FOUND_PATH, request.url));
  }

  if (isMarkdownPreferred(request)) {
    const target = [docsContentRoute, slug, "content.md"]
      .filter(Boolean)
      .join("/");
    const response = NextResponse.rewrite(new URL(target, request.url));
    response.headers.set("Vary", "Accept");
    return response;
  }

  const response = NextResponse.next();
  response.headers.set("Vary", "Accept");
  return response;
}

export const config = {
  matcher: ["/docs", "/docs/((?!_next/|og/|api/|.*\\.(?:md|txt|xml)$).*)"],
};
