import { describe, expect, it } from "vitest";

import type { PublishedContentEntry } from "../../../src/blocks/content/content.ts";

import {
  articleJsonLd,
  breadcrumbJsonLd,
  jsonLdScript,
  robotsTxt,
  sitemapChunks,
  sitemapIndexXml,
  sitemapXml,
} from "../../../src/blocks/content/seo.ts";

const entry = (
  patch: Partial<PublishedContentEntry> = {},
): PublishedContentEntry => ({
  id: "e-1",
  type: "post",
  locale: "en",
  slug: "hello & goodbye",
  title: "Hello </script>",
  translationGroupId: "g",
  publishedAt: Temporal.Instant.from("2026-10-01T10:00:00Z"),
  updatedAt: Temporal.Instant.from("2026-10-02T10:00:00Z"),
  ...patch,
});

const urlFor = (item: PublishedContentEntry): string =>
  `https://site.example/${item.locale}/${encodeURIComponent(item.slug)}`;

describe("sitemapXml", () => {
  it("lists entries with lastmod and escapes the URL", () => {
    const xml = sitemapXml([entry()], { urlFor });

    expect(xml).toContain(
      "<loc>https://site.example/en/hello%20%26%20goodbye</loc>",
    );
    expect(xml).toContain("<lastmod>2026-10-02T10:00:00Z</lastmod>");
    expect(xml).toContain(
      'xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"',
    );
  });

  it("adds hreflang alternates for translations", () => {
    const xml = sitemapXml(
      [entry({ translations: [{ locale: "nl", slug: "hallo" }] })],
      {
        urlFor,
        translationUrlFor: (_e, t) =>
          `https://site.example/${t.locale}/${t.slug}`,
      },
    );

    expect(xml).toContain('hreflang="nl" href="https://site.example/nl/hallo"');
    expect(xml).toContain('hreflang="en"');
  });

  it("refuses relative and non-http URLs and too many entries", () => {
    expect(() => sitemapXml([entry()], { urlFor: () => "/relative" })).toThrow(
      TypeError,
    );
    expect(() =>
      sitemapXml([entry()], {
        urlFor: () => ["java", "script:alert(1)"].join(""),
      }),
    ).toThrow(TypeError);
    expect(() =>
      sitemapXml(
        Array.from({ length: 50_001 }, () => entry()),
        { urlFor },
      ),
    ).toThrow(RangeError);
  });

  it("splits entries and writes an index", () => {
    expect(sitemapChunks([1, 2, 3, 4, 5], 2)).toEqual([[1, 2], [3, 4], [5]]);
    expect(() => sitemapChunks([1], 0)).toThrow(RangeError);
    expect(
      sitemapIndexXml([
        {
          url: "https://site.example/s1.xml",
          lastModified: Temporal.Instant.from("2026-10-01T00:00:00Z"),
        },
      ]),
    ).toContain(
      "<sitemap><loc>https://site.example/s1.xml</loc><lastmod>2026-10-01T00:00:00Z</lastmod></sitemap>",
    );
  });
});

describe("robotsTxt", () => {
  it("writes rules and sitemap lines", () => {
    expect(
      robotsTxt({
        disallow: ["/admin"],
        sitemaps: ["https://site.example/sitemap.xml"],
      }),
    ).toBe(
      "User-agent: *\nDisallow: /admin\nSitemap: https://site.example/sitemap.xml\n",
    );
    expect(robotsTxt()).toBe("User-agent: *\nDisallow:\n");
  });

  it("refuses a path with a line break", () => {
    expect(() => robotsTxt({ disallow: ["/a\nAllow: /"] })).toThrow(TypeError);
  });
});

describe("structured data", () => {
  it("writes Article and BreadcrumbList", () => {
    const article = articleJsonLd(entry({ summary: "S" }), {
      url: "https://site.example/en/x",
      author: "Ada",
      publisher: { name: "Site", logoUrl: "https://site.example/l.png" },
    });

    expect(article).toMatchObject({
      "@type": "Article",
      headline: "Hello </script>",
      description: "S",
      datePublished: "2026-10-01T10:00:00Z",
      author: { name: "Ada" },
    });
    expect(
      breadcrumbJsonLd([
        { name: "Home", url: "https://site.example/" },
        { name: "Blog", url: "https://site.example/blog" },
      ]),
    ).toMatchObject({
      itemListElement: [{ position: 1 }, { position: 2, name: "Blog" }],
    });
  });

  it("escapes the script text so a title cannot close the element", () => {
    const text = jsonLdScript(
      articleJsonLd(entry(), { url: "https://site.example/x" }),
    );

    expect(text).not.toContain("</script>");
    expect(text).not.toContain("<");
    expect(JSON.parse(text).headline).toBe("Hello </script>");
  });
});
