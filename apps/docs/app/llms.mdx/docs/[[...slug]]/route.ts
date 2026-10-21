import { notFound } from "next/navigation";

import {
  getPageMarkdown,
  getPageMarkdownUrl,
  markdownHeaders,
  source,
} from "@/lib/source";

type MarkdownRouteContext = { params: Promise<{ slug?: string[] }> };

export async function GET(
  _req: Request,
  context: MarkdownRouteContext,
): Promise<Response> {
  const { slug } = await context.params;
  // Drop the appended `content.md`; `/docs/index.md` is the root page.
  const slugs = slug?.slice(0, -1) ?? [];

  if (slugs.at(-1) === "index") {
    slugs.pop();
  }

  const page = source.getPage(slugs);

  if (!page) {
    notFound();
  }

  const markdown = await getPageMarkdown(page.url);

  if (markdown === undefined) {
    notFound();
  }

  return new Response(markdown, { headers: markdownHeaders });
}

export function generateStaticParams() {
  return [
    ...source
      .getPages()
      .map((page) => ({ slug: getPageMarkdownUrl(page).segments })),
    { slug: ["index", "content.md"] },
  ];
}
