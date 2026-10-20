import { existsSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, test } from "vitest";

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

function hasDocsPage(href: string): boolean {
  const path = href.replace(/^\/docs\/?/, "");

  return (
    existsSync(join(DOCS, `${path}.mdx`)) ||
    existsSync(join(DOCS, path, "index.mdx"))
  );
}

describe("integrations", () => {
  test("every frameworks docs page is linked", () => {
    const hrefs = new Set(integrations.map((integration) => integration.href));

    const missing = readdirSync(join(DOCS, "frameworks"))
      .filter((file) => file.endsWith(".mdx"))
      .map((file) => file.replace(/\.mdx$/, ""))
      .filter((slug) => !UNLISTED.has(slug))
      .filter((slug) => !hrefs.has(`/docs/frameworks/${slug}`));

    expect(missing).toEqual([]);
  });

  test("every entry links to a docs page and has a logo", () => {
    const broken = integrations
      .filter(
        (integration) =>
          !hasDocsPage(integration.href) ||
          !/^[Mm]/.test(integration.mark.path),
      )
      .map((integration) => integration.name);

    expect(broken).toEqual([]);
  });

  test("names are unique and every group has entries", () => {
    const names = integrations.map((integration) => integration.name);

    const empty = integrationGroups.filter(
      (name) => integrationsIn(name).length === 0,
    );

    expect(new Set(names).size).toBe(names.length);
    expect(empty).toEqual([]);
  });

  test("the count line follows the list", () => {
    const servers = integrationsIn("Server frameworks").length;

    expect(integrationCounts()).toMatch(
      new RegExp(`^${String(servers)} frameworks, .+ and \\d+ integrations$`),
    );
  });
});
