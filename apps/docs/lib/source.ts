import { loader } from "fumadocs-core/source";
import { lucideIconsPlugin } from "fumadocs-core/source/lucide-icons";
import { metaSchema, pageSchema } from "fumadocs-core/source/schema";
import { defineDocs } from "fumadocs-mdx/macro";

import type { DocsPageSummary } from "./page-search";

import { docsContentRoute, docsRoute } from "./shared";

const docs = defineDocs({
  dir: "content/docs",
  docs: {
    schema: pageSchema,
    postprocess: { includeProcessedMarkdown: true },
    // Git history; Vercel needs VERCEL_DEEP_CLONE=true for real dates.
    lastModified: true,
  },
  meta: { schema: metaSchema },
});

export const source = loader({
  baseUrl: docsRoute,
  source: docs.toFumadocsSource(),
  plugins: [lucideIconsPlugin()],
});

export type DocsPage = (typeof source)["$inferPage"];

export function getPageMarkdownUrl(page: DocsPage) {
  const segments = [...page.slugs, "content.md"];
  return {
    segments,
    url:
      "/" +
      [...docsContentRoute.split("/"), ...segments].filter(Boolean).join("/"),
  };
}

/** The page catalog Ask AI searches. */
export function getPageSummaries(): readonly DocsPageSummary[] {
  return source.getPages().map((page) => ({
    title: page.data.title,
    description: page.data.description ?? "",
    url: page.url,
    slugs: page.slugs,
  }));
}

/** OG image route for a page, served by `app/docs/og/[...slug]/route.tsx`. */
export function getPageImage(page: DocsPage) {
  const segments = [...page.slugs, "image.png"];
  return { segments, url: `${docsRoute}/og/${segments.join("/")}` };
}

export async function getLLMText(page: DocsPage) {
  const processed = await page.data.getText("processed");
  return `# ${page.data.title} (${page.url})\n\n${processed}`;
}
