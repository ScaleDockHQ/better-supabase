import type { NextRequest } from "next/server";

import { NextResponse } from "next/server";

import catalog from "./lib/catalog.json" with { type: "json" };

const blockNames: ReadonlySet<string> = new Set(
  catalog.blocks.map((block) => block.name),
);

/** No route matches it, so Next renders `app/global-not-found.tsx` with a 404. */
const NOT_FOUND_PATH = "/_not-found-blocks";

/**
 * Unknown block URLs answer 404 instead of a streamed 200: under Cache
 * Components `notFound()` can't change the status of a path that
 * `generateStaticParams` did not list.
 */
export function proxy(request: NextRequest): NextResponse {
  const name = request.nextUrl.pathname.slice("/blocks/".length);
  if (blockNames.has(name)) return NextResponse.next();
  return NextResponse.rewrite(new URL(NOT_FOUND_PATH, request.url));
}

export const config = {
  matcher: ["/blocks/:name"],
};
