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

const prefersMarkdown = (request: NextRequest): boolean =>
  (request.headers.get("accept") ?? "").includes("text/markdown");

/**
 * Unknown block and recipe URLs answer 404 instead of a streamed 200: under
 * Cache Components `notFound()` can't change the status of a path that
 * `generateStaticParams` did not list. `<url>.md`, or a request that asks for
 * Markdown (`Accept: text/markdown`), gets the page as Markdown.
 */
export function proxy(request: NextRequest): NextResponse {
  const [, section = "", segment = ""] = request.nextUrl.pathname.split("/");
  const extension = /\.[a-z0-9]+$/i.exec(segment)?.[0] ?? "";

  // Static files such as /recipes/<slug>.png come from public/, and
  // /blocks/opengraph-image is the index page's generated image.
  if (
    (extension !== "" && extension !== ".md") ||
    segment.startsWith("opengraph-image")
  ) {
    return NextResponse.next();
  }

  const name = segment.slice(0, segment.length - extension.length);
  const known = section === "blocks" ? blockNames : recipeSlugs;

  if (!known.has(name)) {
    return NextResponse.rewrite(new URL(NOT_FOUND_PATH, request.url));
  }

  const response =
    extension === ".md" || prefersMarkdown(request)
      ? NextResponse.rewrite(
          new URL(`/markdown/${section}/${name}`, request.url),
        )
      : NextResponse.next();

  response.headers.set("Vary", "Accept");

  return response;
}

export const config = { matcher: ["/blocks/:name", "/recipes/:slug"] };
