import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

import { COMMUNITY_ADAPTERS, SUPPORTED_ADAPTERS } from "./tiers.ts";

const manifest: { exports: Record<string, unknown> } = JSON.parse(
  readFileSync(new URL("../../package.json", import.meta.url), "utf-8"),
);

const page = (slug: string): string =>
  readFileSync(
    new URL(
      `../../../../apps/docs/content/docs/(docs)/frameworks/${slug}.mdx`,
      import.meta.url,
    ),
    "utf-8",
  );

describe("adapter tiers", () => {
  it("names shipped subpaths, each in one tier", () => {
    const supported = Object.keys(SUPPORTED_ADAPTERS);
    const community = Object.keys(COMMUNITY_ADAPTERS);

    for (const subpath of [...supported, ...community]) {
      expect(manifest.exports).toHaveProperty([`./${subpath}`]);
    }

    expect(supported.filter((name) => community.includes(name))).toEqual([]);
  });

  it("marks every community page and lists the tiers on the overview", () => {
    for (const slug of new Set(Object.values(COMMUNITY_ADAPTERS))) {
      expect(page(slug)).toContain("/docs/frameworks#adapter-tiers");
    }

    for (const slug of new Set(Object.values(SUPPORTED_ADAPTERS))) {
      expect(page(slug)).not.toContain("Community adapter");
    }

    expect(page("index")).toContain("## Adapter tiers");
  });
});
