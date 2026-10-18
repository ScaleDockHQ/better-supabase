import type { Metadata } from "next";

import { Suspense } from "react";

import { BlockDetail } from "@/features/blocks/components/block-detail";
import { DetailSkeleton } from "@/features/catalog/components/detail-skeleton";
import { blockPath, blockStaticParams, getBlock } from "@/lib/blocks";

interface BlockPageProps {
  readonly params: Promise<{ name: string }>;
}

export function generateStaticParams(): { name: string }[] {
  return blockStaticParams();
}

export async function generateMetadata({
  params,
}: BlockPageProps): Promise<Metadata> {
  const block = getBlock((await params).name);

  if (!block) {
    return {};
  }

  const path = blockPath(block.name);

  return {
    title: `${block.title} block`,
    description: block.description,
    alternates: {
      canonical: path,
      types: { "text/markdown": `${path}.md` },
    },
    openGraph: { url: path },
  };
}

export default function BlockPage({ params }: BlockPageProps) {
  return (
    <Suspense fallback={<DetailSkeleton />}>
      <BlockDetail params={params} />
    </Suspense>
  );
}
