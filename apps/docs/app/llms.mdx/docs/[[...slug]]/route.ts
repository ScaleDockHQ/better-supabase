import { notFound } from "next/navigation";

import {
  docsLlms,
  getPageMarkdownUrl,
  markdownHeaders,
  source,
} from "@/lib/source";

type MarkdownRouteContext = {
  params: Promise<{ slug?: string[] }>;
};

export async function GET(
  _req: Request,
  context: MarkdownRouteContext,
): Promise<Response> {
  const { slug } = await context.params;
  // Drop the appended `content.md`; `/docs/index.md` is the root page.
  const slugs = slug?.slice(0, -1) ?? [];
  if (slugs.at(-1) === "index") slugs.pop();
  const page = source.getPage(slugs);
  if (!page) notFound();

  return new Response(await docsLlms.page(page), { headers: markdownHeaders });
}

export function generateStaticParams() {
  return [
    ...source.getPages().map((page) => ({
      slug: getPageMarkdownUrl(page).segments,
    })),
    { slug: ["index", "content.md"] },
  ];
}
