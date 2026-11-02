import type { PublishedContentEntry } from "./content.ts";

/** The most URLs a sitemap file may list (sitemaps.org protocol 0.9). */
export const SITEMAP_MAX_URLS = 50_000;

export interface SitemapOptions {
  /** The absolute URL of an entry's page in its own locale. */
  readonly urlFor: (entry: PublishedContentEntry) => string;
  /**
   * The absolute URL of a translation's page, for `hreflang` alternates. Left
   * out, the sitemap carries no alternates.
   */
  readonly translationUrlFor?: (
    entry: PublishedContentEntry,
    translation: { readonly locale: string; readonly slug: string },
  ) => string;
  /** The `changefreq` hint. Search engines mostly ignore it; default none. */
  readonly changeFrequency?:
    | "always"
    | "hourly"
    | "daily"
    | "weekly"
    | "monthly"
    | "yearly"
    | "never";
}

const XML_ENTITIES: Readonly<Record<string, string>> = {
  "&": "&amp;",
  "<": "&lt;",
  ">": "&gt;",
  '"': "&quot;",
  "'": "&apos;",
};

function xml(text: string): string {
  return text.replaceAll(/[&<>"']/g, (char) => XML_ENTITIES[char] ?? char);
}

function absolute(url: string): string {
  const parsed = new URL(url);

  if (parsed.protocol !== "https:" && parsed.protocol !== "http:") {
    throw new TypeError(`A sitemap URL must be http or https: ${url}`);
  }

  return parsed.toString();
}

/**
 * A sitemap (sitemaps.org 0.9) of published entries, with `lastmod` from the
 * entry's update time and `hreflang` alternates from its translations. More
 * than 50,000 entries throws: split them with `sitemapChunks` and list the
 * files in `sitemapIndexXml`. URLs are escaped and must be absolute.
 */
export function sitemapXml(
  entries: readonly PublishedContentEntry[],
  options: SitemapOptions,
): string {
  if (entries.length > SITEMAP_MAX_URLS) {
    throw new RangeError(
      `A sitemap lists at most ${SITEMAP_MAX_URLS} URLs; split the entries with sitemapChunks`,
    );
  }

  const urls = entries.map((entry) => {
    const alternates = (entry.translations ?? []).flatMap((translation) =>
      options.translationUrlFor === undefined
        ? []
        : [
            `<xhtml:link rel="alternate" hreflang="${xml(translation.locale)}" href="${xml(absolute(options.translationUrlFor(entry, translation)))}"/>`,
          ],
    );

    const own =
      alternates.length === 0
        ? []
        : [
            `<xhtml:link rel="alternate" hreflang="${xml(entry.locale)}" href="${xml(absolute(options.urlFor(entry)))}"/>`,
          ];

    return [
      "<url>",
      `<loc>${xml(absolute(options.urlFor(entry)))}</loc>`,
      `<lastmod>${entry.updatedAt.toString()}</lastmod>`,
      ...(options.changeFrequency === undefined
        ? []
        : [`<changefreq>${options.changeFrequency}</changefreq>`]),
      ...own,
      ...alternates,
      "</url>",
    ].join("");
  });

  return `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">${urls.join("")}</urlset>\n`;
}

/** Splits entries into groups a single sitemap file can hold. */
export function sitemapChunks<T>(
  entries: readonly T[],
  size: number = SITEMAP_MAX_URLS,
): T[][] {
  if (!Number.isInteger(size) || size < 1 || size > SITEMAP_MAX_URLS) {
    throw new RangeError(`A chunk holds 1 to ${SITEMAP_MAX_URLS} entries`);
  }

  const chunks: T[][] = [];

  for (let index = 0; index < entries.length; index += size) {
    chunks.push(entries.slice(index, index + size));
  }

  return chunks;
}

/** A sitemap index that lists sitemap files by absolute URL. */
export function sitemapIndexXml(
  files: readonly {
    readonly url: string;
    readonly lastModified?: Temporal.Instant;
  }[],
): string {
  const items = files.map(
    (file) =>
      `<sitemap><loc>${xml(absolute(file.url))}</loc>${file.lastModified === undefined ? "" : `<lastmod>${file.lastModified.toString()}</lastmod>`}</sitemap>`,
  );

  return `<?xml version="1.0" encoding="UTF-8"?>\n<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">${items.join("")}</sitemapindex>\n`;
}

export interface RobotsOptions {
  /** Absolute sitemap URLs. */
  readonly sitemaps?: readonly string[];
  /** Paths crawlers may not fetch for every agent. Default none. */
  readonly disallow?: readonly string[];
  readonly allow?: readonly string[];
}

/** A `robots.txt` (RFC 9309) for all user agents. */
export function robotsTxt(options: RobotsOptions = {}): string {
  const lines = [
    "User-agent: *",
    ...(options.allow ?? []).map((path) => `Allow: ${path}`),
    ...((options.disallow ?? []).length === 0
      ? ["Disallow:"]
      : (options.disallow ?? []).map((path) => `Disallow: ${path}`)),
    ...(options.sitemaps ?? []).map((url) => `Sitemap: ${absolute(url)}`),
  ];

  for (const line of lines) {
    if (line.includes("\n") || line.includes("\r")) {
      throw new TypeError("A robots.txt line cannot contain a line break");
    }
  }

  return `${lines.join("\n")}\n`;
}

/** A JSON-LD object (schema.org vocabulary). */
export type JsonLd = Readonly<Record<string, unknown>>;

export interface ArticleJsonLdOptions {
  readonly url: string;
  /** The author's name, or a person or organization object. */
  readonly author?: string;
  readonly publisher?: { readonly name: string; readonly logoUrl?: string };
  readonly imageUrl?: string;
  /** `Article`, `BlogPosting` or `NewsArticle`. Default `Article`. */
  readonly type?: "Article" | "BlogPosting" | "NewsArticle";
}

/** Schema.org `Article` structured data for a published entry. */
export function articleJsonLd(
  entry: PublishedContentEntry,
  options: ArticleJsonLdOptions,
): JsonLd {
  return {
    "@context": "https://schema.org",
    "@type": options.type ?? "Article",
    headline: entry.title,
    ...(entry.summary === undefined ? {} : { description: entry.summary }),
    inLanguage: entry.locale,
    mainEntityOfPage: { "@type": "WebPage", "@id": absolute(options.url) },
    datePublished: entry.publishedAt.toString(),
    dateModified: entry.updatedAt.toString(),
    ...(options.imageUrl === undefined
      ? {}
      : { image: absolute(options.imageUrl) }),
    ...(options.author === undefined
      ? {}
      : { author: { "@type": "Person", name: options.author } }),
    ...(options.publisher === undefined
      ? {}
      : {
          publisher: {
            "@type": "Organization",
            name: options.publisher.name,
            ...(options.publisher.logoUrl === undefined
              ? {}
              : {
                  logo: {
                    "@type": "ImageObject",
                    url: absolute(options.publisher.logoUrl),
                  },
                }),
          },
        }),
  };
}

/** Schema.org `BreadcrumbList`, positions counted from 1. */
export function breadcrumbJsonLd(
  trail: readonly { readonly name: string; readonly url: string }[],
): JsonLd {
  return {
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    itemListElement: trail.map((item, index) => ({
      "@type": "ListItem",
      position: index + 1,
      name: item.name,
      item: absolute(item.url),
    })),
  };
}

/**
 * The JSON text for a `<script type="application/ld+json">` element. `<`, `>`
 * and `&` and the line separators are escaped as `\uXXXX`, so a title with
 * `</script>` cannot close the element.
 */
export function jsonLdScript(data: JsonLd | readonly JsonLd[]): string {
  return JSON.stringify(data)
    .replaceAll("<", String.raw`\u003c`)
    .replaceAll(">", String.raw`\u003e`)
    .replaceAll("&", String.raw`\u0026`)
    .replaceAll("\u2028", String.raw`\u2028`)
    .replaceAll("\u2029", String.raw`\u2029`);
}
