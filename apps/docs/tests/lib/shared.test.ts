import { describe, expect, it } from "vitest";

import { docsUrl, markdownUrl } from "../../lib/shared";

describe("docsUrl", () => {
  it("normalizes paths, hosts, suffixes and anchors", () => {
    expect(docsUrl("/docs/frameworks/hono")).toBe("/docs/frameworks/hono");
    expect(docsUrl("frameworks/hono/")).toBe("/docs/frameworks/hono");
    expect(docsUrl("https://bettersupabase.com/docs/cli/gen.md?x=1")).toBe(
      "/docs/cli/gen",
    );
    expect(docsUrl("/docs")).toBe("/docs");
  });
});

describe("markdownUrl", () => {
  it("appends .md, so the docs root is /docs.md", () => {
    expect(markdownUrl("/docs")).toBe("/docs.md");
    expect(markdownUrl("/docs/cli/")).toBe("/docs/cli.md");
  });
});
