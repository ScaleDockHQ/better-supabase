import { blockStaticParams, getBlock } from "@/lib/blocks";
import { OgImage, ogSize } from "@/lib/og";

export const alt = "A better-supabase block";
export const size = ogSize;
export const contentType = "image/png";

export function generateStaticParams(): { name: string }[] {
  return blockStaticParams();
}

export default async function Image({
  params,
}: {
  readonly params: Promise<{ name: string }>;
}) {
  const block = getBlock((await params).name);

  return OgImage({
    eyebrow: block ? `Block / ${block.category}` : "Block",
    title: block?.title ?? "Block",
    description: block?.description ?? "",
  });
}
