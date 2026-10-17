import { llms, loader } from "fumadocs-core/source";
import { lucideIconsPlugin } from "fumadocs-core/source/lucide-icons";
import { metaSchema, pageSchema } from "fumadocs-core/source/schema";
import { defineDocs } from "fumadocs-mdx/macro";
import { cacheLife } from "next/cache";

import { markdownComponents } from "@/components/mdx-markdown";

import type { DocsPageSummary } from "./page-search";

import { formatLLMIndex } from "./llms";
import { docsContentRoute, docsRoute, markdownUrl } from "./shared";
import { siteUrl } from "./site-url";

const docs = defineDocs({
  dir: "content/docs",
  docs: {
    schema: pageSchema,
    postprocess: { includeProcessedMarkdown: { output: "function" } },
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

/** The internal route that serves a page's Markdown; `/docs/x.md` rewrites to it. */
export function getPageMarkdownUrl(page: DocsPage) {
  const segments = [...page.slugs, "content.md"];
  return {
    segments,
    url: `/${[...docsContentRoute.split("/"), ...segments]
      .filter(Boolean)
      .join("/")}`,
  };
}

/** The public Markdown URL of a page, such as `/docs/cli.md` or `/docs.md`. */
export function getPagePublicMarkdownUrl(page: DocsPage): string {
  return markdownUrl(page.url);
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

/** Each page as Markdown: `llms-full.txt`, the `.md` routes, Ask AI and the docs MCP server. */
const docsLlms = llms(source, {
  async renderPage(page) {
    const description = page.data.description?.trim();
    const processed = await page.data.getText("processed", {
      components: markdownComponents,
    });
    return [
      `# ${page.data.title}`,
      description === undefined || description === ""
        ? ""
        : `\n> ${description}\n`,
      `Source: ${siteUrl(page.url)}`,
      "",
      processed,
    ].join("\n");
  },
});

const LLMS_DETAILS = `better-supabase is a TypeScript library for Supabase: typed repositories
compiled to PostgREST, auth for every caller, framework adapters, blocks
(SQL modules with typed APIs) and a CLI for codegen and doctor checks.

Every page below is Markdown. Add \`.md\` to a page URL, or send
\`Accept: text/markdown\`, to read any other page the same way.`;

/** `llms.txt`; the pages only change with a deploy. */
// oxlint-disable-next-line typescript/require-await -- a "use cache" function must be async
export async function getLLMIndex(): Promise<string> {
  "use cache";
  cacheLife("max");
  return formatLLMIndex(source.getPageTree(), {
    title: "better-supabase",
    summary:
      source.getPage([])?.data.description ??
      "A strongly typed layer over Supabase.",
    details: LLMS_DETAILS,
    describe: (item) => source.getNodePage(item)?.data.description,
    absolute: siteUrl,
    optional: [
      {
        title: "Full documentation",
        url: siteUrl("/llms-full.txt"),
        description: "every page in one Markdown file",
      },
      {
        title: "Docs MCP server",
        url: siteUrl("/mcp"),
        description:
          "Streamable HTTP, read-only tools search_docs, get_page and list_pages",
      },
    ],
  });
}

/** `llms-full.txt`: every page as Markdown in one file. */
export async function getFullMarkdown(): Promise<string> {
  "use cache";
  cacheLife("max");
  return docsLlms.full();
}

/** One page as Markdown by its docs URL, or `undefined` when no page has it. */
export async function getPageMarkdown(
  url: string,
): Promise<string | undefined> {
  "use cache";
  cacheLife("max");
  const page = source.getPageByUrl(url);
  return page === undefined ? undefined : docsLlms.page(page);
}

/** Response headers for the Markdown routes agents read. */
export const markdownHeaders = {
  "Content-Type": "text/markdown; charset=utf-8",
  "Cache-Control": "public, max-age=3600, stale-while-revalidate=86400",
  Vary: "Accept",
};
