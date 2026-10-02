import type { Metadata } from "next";

import { notFound } from "next/navigation";
import { Suspense } from "react";

import { DocsArticle, DocsArticleSkeleton } from "@/components/docs-article";
import { siteUrl } from "@/lib/site-url";
import { getPageImage, source } from "@/lib/source";

type DocsPageProps = {
  params: Promise<{ slug?: string[] }>;
};

export default function Page({ params }: DocsPageProps) {
  // The slug is URL data, so the article sits outside the shared App Shell.
  return (
    <Suspense fallback={<DocsArticleSkeleton />}>
      <DocsArticle slug={params.then((resolved) => resolved.slug)} />
    </Suspense>
  );
}

export function generateStaticParams() {
  return source.generateParams();
}

export async function generateMetadata(
  props: DocsPageProps,
): Promise<Metadata> {
  const params = await props.params;
  const page = source.getPage(params.slug);
  if (!page) notFound();

  const image = siteUrl(getPageImage(page).url);
  return {
    title: page.data.title,
    description: page.data.description,
    alternates: { canonical: siteUrl(page.url) },
    openGraph: { images: image },
    twitter: { card: "summary_large_image", images: image },
  };
}
