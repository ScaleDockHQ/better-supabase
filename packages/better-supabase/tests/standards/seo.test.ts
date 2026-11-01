import { describe, expect, it } from "vitest";

import {
  articleJsonLd,
  robotsTxt,
  SITEMAP_MAX_URLS,
  sitemapXml,
} from "../../src/blocks/content/seo.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";

const entry = {
  id: "e",
  type: "post",
  locale: "en",
  slug: "a",
  title: "T",
  translationGroupId: "g",
  publishedAt: Temporal.Instant.from("2026-01-01T00:00:00Z"),
  updatedAt: Temporal.Instant.from("2026-01-02T00:00:00Z"),
} as const;

describe(`sitemaps.org protocol ${SPEC_PINS.sitemaps}`, () => {
  it("uses the 0.9 namespace and the 50,000 URL limit", () => {
    expect(SPEC_PINS.sitemaps).toBe("0.9");
    expect(SITEMAP_MAX_URLS).toBe(50_000);
    expect(
      sitemapXml([entry], { urlFor: () => "https://s.example/a" }),
    ).toContain(
      `<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/${SPEC_PINS.sitemaps}"`,
    );
  });
});

describe(`RFC 9309 robots.txt ${SPEC_PINS.rfc9309}`, () => {
  it("starts a group with User-agent and ends lines with a line feed", () => {
    expect(SPEC_PINS.rfc9309).toBe("2022-09");
    expect(robotsTxt({ disallow: ["/x"] })).toBe(
      "User-agent: *\nDisallow: /x\n",
    );
  });
});

describe(`JSON-LD ${SPEC_PINS.jsonLd}`, () => {
  it("writes schema.org terms with a context and a type", () => {
    expect(SPEC_PINS.jsonLd).toBe("1.1");
    expect(articleJsonLd(entry, { url: "https://s.example/a" })).toMatchObject({
      "@context": "https://schema.org",
      "@type": "Article",
    });
  });
});
