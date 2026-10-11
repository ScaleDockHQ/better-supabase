import { readdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

import { pageSlug } from "../lib/page-slugs.ts";

const CONTENT_DIR = join(import.meta.dirname, "../content/docs");

/** The file `proxy.ts` reads; `dev` and `build` rewrite it, a test checks it is current. */
export const PAGE_SLUGS_FILE = join(
  import.meta.dirname,
  "../lib/page-slugs.json",
);

/** Every page slug under `content/docs`, sorted. */
export function readPageSlugs(dir: string = CONTENT_DIR): string[] {
  return readdirSync(dir, { recursive: true, encoding: "utf8" })
    .flatMap((file) => {
      const slug = pageSlug(file);
      return slug === undefined ? [] : [slug];
    })
    .toSorted();
}

export function formatPageSlugs(slugs: readonly string[]): string {
  return `${JSON.stringify(slugs, null, 2)}\n`;
}

if (import.meta.main) {
  writeFileSync(PAGE_SLUGS_FILE, formatPageSlugs(readPageSlugs()));
}
