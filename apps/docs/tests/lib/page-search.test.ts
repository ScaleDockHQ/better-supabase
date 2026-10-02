import { describe, expect, it } from "vitest";

import { type DocsPageSummary, searchDocs } from "../../lib/page-search";

const pages: readonly DocsPageSummary[] = [
  {
    title: "Hono",
    description: "Middleware and REST resources for Hono",
    url: "/docs/frameworks/hono",
    slugs: ["frameworks", "hono"],
  },
  {
    title: "Extension interfaces",
    description: "Executors, caches and sinks",
    url: "/docs/extending/interfaces",
    slugs: ["extending", "interfaces"],
  },
  {
    title: "Quickstart",
    description: "Install and generate",
    url: "/docs/getting-started",
    slugs: ["getting-started"],
  },
];

describe("searchDocs", () => {
  it("ranks title matches above path matches", () => {
    const hits = searchDocs(pages, "hono");
    expect(hits[0]?.url).toBe("/docs/frameworks/hono");
  });

  it("returns nothing for an empty query", () => {
    expect(searchDocs(pages, "   ")).toEqual([]);
  });

  it("caps the limit", () => {
    expect(searchDocs(pages, "hono", 1)).toHaveLength(1);
  });
});
