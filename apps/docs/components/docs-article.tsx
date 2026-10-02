import {
  DocsBody,
  DocsDescription,
  DocsPage,
  DocsTitle,
  MarkdownCopyButton,
  PageLastUpdate,
  ViewOptionsPopover,
} from "fumadocs-ui/layouts/docs/page";
import { createRelativeLink } from "fumadocs-ui/mdx";
import { notFound } from "next/navigation";

import { getMDXComponents } from "@/components/mdx";
import { gitConfig } from "@/lib/shared";
import { getPageMarkdownUrl, source } from "@/lib/source";

/** One docs page: the MDX body, the copy and view actions, and the last edit date. */
export async function DocsArticle({
  slug,
}: {
  slug: Promise<string[] | undefined>;
}) {
  const page = source.getPage(await slug);
  if (!page) notFound();

  const MDX = page.data.body;
  const markdownUrl = getPageMarkdownUrl(page).url;
  const { lastModified } = page.data;

  return (
    <DocsPage toc={page.data.toc} full={page.data.full}>
      <DocsTitle>{page.data.title}</DocsTitle>
      <DocsDescription className="mb-0">
        {page.data.description}
      </DocsDescription>
      <div className="flex flex-row items-center gap-2 border-b pb-6">
        <MarkdownCopyButton markdownUrl={markdownUrl} />
        <ViewOptionsPopover
          markdownUrl={markdownUrl}
          githubUrl={`https://github.com/${gitConfig.user}/${gitConfig.repo}/blob/${gitConfig.branch}/${gitConfig.contentDir}/${page.path}`}
        />
      </div>
      <DocsBody>
        <MDX
          components={getMDXComponents({
            a: createRelativeLink(source, page),
          })}
        />
      </DocsBody>
      {lastModified === undefined ? null : (
        <PageLastUpdate date={new Date(lastModified)} />
      )}
    </DocsPage>
  );
}

/** Holds the article's place while a navigation without a prefetch streams it in. */
export function DocsArticleSkeleton() {
  return (
    <div
      aria-busy="true"
      className="mx-auto flex w-full max-w-[900px] flex-1 flex-col gap-4 px-4 pt-8 md:px-6 md:pt-12"
    >
      <div className="bg-fd-muted h-9 w-2/3 rounded-md motion-safe:animate-pulse" />
      <div className="bg-fd-muted h-5 w-full rounded-md motion-safe:animate-pulse" />
    </div>
  );
}
