import type { MetadataRoute } from "next";

import { siteUrl } from "@/lib/site-url";
import { source } from "@/lib/source";

/** Served at /docs/sitemap.xml; the marketing app's robots.txt lists it. */
export default function sitemap(): MetadataRoute.Sitemap {
  return source.getPages().map((page) => ({
    url: siteUrl(page.url),
    ...(page.data.lastModified === undefined
      ? {}
      : { lastModified: new Date(page.data.lastModified) }),
  }));
}
