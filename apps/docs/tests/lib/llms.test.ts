import type { Item, Root } from "fumadocs-core/page-tree";

import { describe, expect, it } from "vitest";

import type { LLMIndexOptions } from "../../lib/llms";

import { formatLLMIndex } from "../../lib/llms";

const page = (name: string, url: string): Item => ({ type: "page", name, url });

const tree: Root = {
  name: "Docs",
  children: [
    page("Introduction", "/docs"),
    { type: "separator", name: "Guides" },
    {
      type: "folder",
      name: "Guides",
      index: page("Overview", "/docs/guides"),
      children: [page("Data [API] grants", "/docs/guides/data-api-grants")],
    },
    { type: "folder", name: "CLI", children: [page("gen", "/docs/cli/gen")] },
    {
      type: "page",
      name: "GitHub",
      url: "https://github.com/ScaleDockHQ/better-supabase",
      external: true,
    },
    { type: "separator", name: "Empty" },
  ],
};

const DESCRIPTIONS = new Map([
  ["/docs", "What it is."],
  ["/docs/cli/gen", "  Codegen.  "],
]);

const options: LLMIndexOptions = {
  title: "better-supabase",
  summary: "A TypeScript library for Supabase.",
  details: "Pages link to Markdown.",
  describe: (item) => DESCRIPTIONS.get(item.url),
  absolute: (path) => `https://bettersupabase.com${path}`,
  optional: [
    {
      title: "Full docs",
      url: "https://bettersupabase.com/llms-full.txt",
      description: "Every page.",
    },
  ],
};

describe("formatLLMIndex", () => {
  it("writes the llms.txt shape with absolute Markdown links", () => {
    expect(formatLLMIndex(tree, options)).toBe(
      [
        "# better-supabase",
        "",
        "> A TypeScript library for Supabase.",
        "",
        "Pages link to Markdown.",
        "",
        "- [Introduction](https://bettersupabase.com/docs.md): What it is.",
        "",
        "## Guides",
        "",
        "- [Overview](https://bettersupabase.com/docs/guides.md)",
        "- [Data \\[API\\] grants](https://bettersupabase.com/docs/guides/data-api-grants.md)",
        "- CLI",
        "  - [gen](https://bettersupabase.com/docs/cli/gen.md): Codegen.",
        "- [GitHub](https://github.com/ScaleDockHQ/better-supabase)",
        "",
        "## Optional",
        "",
        "- [Full docs](https://bettersupabase.com/llms-full.txt): Every page.",
        "",
      ].join("\n"),
    );
  });

  it("leaves out Optional when there are no optional links", () => {
    expect(formatLLMIndex(tree, { ...options, optional: [] })).not.toContain(
      "## Optional",
    );
  });
});
