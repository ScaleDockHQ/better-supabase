import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

import { assertSameSlugs, docsPathSlug, pageSlug } from "../../lib/page-slugs";
import {
  formatPageSlugs,
  PAGE_SLUGS_FILE,
  readPageSlugs,
} from "../../scripts/page-slugs";

describe("pageSlug", () => {
  it("follows the Fumadocs slug rules", () => {
    expect(pageSlug("index.mdx")).toBe("");
    expect(pageSlug("cli/index.mdx")).toBe("cli");
    expect(pageSlug("cli/doctor.mdx")).toBe("cli/doctor");
    expect(pageSlug("(guides)/csv.mdx")).toBe("csv");
    expect(pageSlug(String.raw`migration\0.5-to-0.6.mdx`)).toBe(
      "migration/0.5-to-0.6",
    );
    expect(pageSlug("notes.md")).toBe("notes");
  });

  it("skips files that are not pages", () => {
    expect(pageSlug("meta.json")).toBeUndefined();
    expect(pageSlug("cli")).toBeUndefined();
  });
});

describe("docsPathSlug", () => {
  it("reads the slug of a docs URL path", () => {
    expect(docsPathSlug("/docs")).toBe("");
    expect(docsPathSlug("/docs/")).toBe("");
    expect(docsPathSlug("/docs/cli/doctor/")).toBe("cli/doctor");
    expect(docsPathSlug("/docs/a%20b")).toBe("a b");
    expect(docsPathSlug("/docs/%E0%A4%A")).toBe("%E0%A4%A");
  });

  it("ignores paths outside /docs", () => {
    expect(docsPathSlug("/")).toBeUndefined();
    expect(docsPathSlug("/docsx")).toBeUndefined();
  });
});

describe("assertSameSlugs", () => {
  it("passes for the same set", () => {
    expect(() => {
      assertSameSlugs(["", "cli"], ["cli", ""]);
    }).not.toThrow();
  });

  it("names the missing pages and the extra slugs", () => {
    expect(() => {
      assertSameSlugs(["", "old"], ["", "new"]);
    }).toThrow(/Missing: new\. Not pages: old\./u);
  });
});

describe("lib/page-slugs.json", () => {
  it("lists every page in content/docs (run node scripts/page-slugs.ts)", () => {
    expect(readFileSync(PAGE_SLUGS_FILE, "utf-8")).toBe(
      formatPageSlugs(readPageSlugs()),
    );
  });
});
