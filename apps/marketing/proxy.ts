import type { NextRequest } from "next/server";

import { NextResponse } from "next/server";

import catalog from "./lib/catalog.json" with { type: "json" };
import recipes from "./lib/recipes.json" with { type: "json" };

const blockNames = new Set(catalog.blocks.map((block) => block.name));
const recipeSlugs = new Set(
  recipes
    .filter((recipe) => recipe.status === "available")
    .map((recipe) => recipe.slug),
);

/** No route matches it, so Next renders `app/global-not-found.tsx` with a 404. */
const NOT_FOUND_PATH = "/_not-found-blocks";

/**
 * Unknown block and recipe URLs answer 404 instead of a streamed 200: under
 * Cache Components `notFound()` can't change the status of a path that
 * `generateStaticParams` did not list.
 */
export function proxy(request: NextRequest): NextResponse {
  const [, section, name = ""] = request.nextUrl.pathname.split("/");
  const known = section === "blocks" ? blockNames : recipeSlugs;
  if (known.has(name)) return NextResponse.next();
  return NextResponse.rewrite(new URL(NOT_FOUND_PATH, request.url));
}

export const config = {
  matcher: ["/blocks/:name", "/recipes/:slug"],
};
