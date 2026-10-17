const CONTENT_FILE = /^(.+)\.mdx?$/u;
const GROUP = /^\(.+\)$/u;

/**
 * The slug of a file under `content/docs`, by the Fumadocs rules: no
 * extension, no `(group)` folders and no trailing `index`. `undefined` for
 * files that are not pages, such as `meta.json`.
 */
export function pageSlug(file: string): string | undefined {
  const path = CONTENT_FILE.exec(file.replaceAll("\\", "/"))?.[1];

  if (path === undefined) {
    return undefined;
  }

  const segments = path.split("/").filter((segment) => !GROUP.test(segment));

  if (segments.at(-1) === "index") {
    segments.pop();
  }

  return segments.join("/");
}

/**
 * Throws when the slugs read from `content/docs` differ from the pages the
 * source loader built, so the proxy never 404s a real page.
 */
export function assertSameSlugs(
  fromFiles: readonly string[],
  fromSource: readonly string[],
): void {
  const files = new Set(fromFiles);
  const pages = new Set(fromSource);
  const missing = [...pages].filter((slug) => !files.has(slug));
  const extra = [...files].filter((slug) => !pages.has(slug));

  if (missing.length === 0 && extra.length === 0) {
    return;
  }

  throw new Error(
    `lib/page-slugs.json is out of date with the docs source. Missing: ${
      missing.join(", ") || "none"
    }. Not pages: ${extra.join(", ") || "none"}. Run node scripts/page-slugs.ts, or update pageSlug().`,
  );
}

/** The page slug a `/docs` URL path asks for, `undefined` outside `/docs`. */
export function docsPathSlug(pathname: string): string | undefined {
  if (pathname !== "/docs" && !pathname.startsWith("/docs/")) {
    return undefined;
  }

  const slug = pathname.slice("/docs".length).replaceAll(/^\/+|\/+$/gu, "");

  try {
    return decodeURIComponent(slug);
  } catch {
    return slug;
  }
}
