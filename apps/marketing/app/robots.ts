import type { MetadataRoute } from "next";

import { site } from "@/lib/site";

export default function robots(): MetadataRoute.Robots {
  return {
    // /markdown/* is where proxy.ts rewrites the public `<page>.md` URLs.
    rules: { userAgent: "*", allow: "/", disallow: ["/markdown/"] },
    // apps/docs serves /docs/sitemap.xml on the same domain.
    sitemap: [`${site.url}/sitemap.xml`, `${site.url}/docs/sitemap.xml`],
  };
}
