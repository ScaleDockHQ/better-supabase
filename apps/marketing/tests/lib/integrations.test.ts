import { globSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import {
  integrationCounts,
  integrationGroups,
  integrations,
  integrationsIn,
} from "../../lib/integrations";

const DOCS = join(import.meta.dirname, "../../../docs/content/docs");

/** Pages under frameworks/ that the home page doesn't list on their own. */
const UNLISTED = new Set([
  "index",
  "other",
  // A Next.js guide, reached from the Next.js page.
  "next-cache-components",
  // A guide for running Hono and Next.js on one server, reached from both pages.
  "hono-and-next",
]);

/** Slugs with `(group)` folders removed, so a moved page still matches its URL. */
const PAGE_SLUGS = new Set(
  globSync("**/*.mdx", { cwd: DOCS }).map((file) =>
    file
      .split("/")
      .filter((part) => !/^\(.+\)$/u.test(part))
      .join("/")
      .replace(/\.mdx$/u, "")
      .replace(/\/index$/u, ""),
  ),
);

function hasDocsPage(href: string): boolean {
  return PAGE_SLUGS.has(href.replace(/^\/docs\/?/u, ""));
}

describe("integrations", () => {
  it("every frameworks docs page is linked", () => {
    const hrefs = new Set(integrations.map((integration) => integration.href));

    const missing = readdirSync(join(DOCS, "(docs)/frameworks"))
      .filter((file) => file.endsWith(".mdx"))
      .map((file) => file.replace(/\.mdx$/, ""))
      .filter((slug) => !UNLISTED.has(slug))
      .filter((slug) => !hrefs.has(`/docs/frameworks/${slug}`));

    expect(missing).toEqual([]);
  });

  it("every entry links to a docs page and has a logo", () => {
    const broken = integrations
      .filter(
        (integration) =>
          !hasDocsPage(integration.href) ||
          !/^[Mm]/.test(integration.mark.path),
      )
      .map((integration) => integration.name);

    expect(broken).toEqual([]);
  });

  it("names are unique and every group has entries", () => {
    const names = integrations.map((integration) => integration.name);

    const empty = integrationGroups.filter(
      (name) => integrationsIn(name).length === 0,
    );

    expect(new Set(names).size).toBe(names.length);
    expect(empty).toEqual([]);
  });

  it("the count line follows the list", () => {
    const servers = integrationsIn("Server frameworks").length;

    expect(integrationCounts()).toMatch(
      new RegExp(`^${String(servers)} frameworks, .+ and \\d+ integrations$`),
    );
  });
});
