import { generateOGImage } from "fumadocs-ui/og";
import { notFound } from "next/navigation";

import { appName } from "@/lib/shared";
import { getPageImage, source } from "@/lib/source";

type ImageRouteContext = {
  params: Promise<{ slug: string[] }>;
};

export async function GET(
  _req: Request,
  context: ImageRouteContext,
): Promise<Response> {
  const { slug } = await context.params;
  const page = source.getPage(slug.slice(0, -1));
  if (!page) notFound();

  return generateOGImage({
    title: page.data.title,
    description: page.data.description,
    site: appName,
    primaryColor: "rgba(62, 207, 142, 0.35)",
    primaryTextColor: "rgb(62, 207, 142)",
  });
}

export function generateStaticParams() {
  return source.getPages().map((page) => ({
    slug: getPageImage(page).segments,
  }));
}
