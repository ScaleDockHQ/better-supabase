import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, test } from "vitest";

import { ALL_CATEGORIES, filterBlocks } from "../../lib/block-filter";
import {
  blockCategories,
  blockPath,
  blocks,
  blockStaticParams,
  blockSummaries,
  configSnippet,
  getBlock,
} from "../../lib/blocks";

const PAGE = join(import.meta.dirname, "../../app/blocks/[name]/page.tsx");

describe("blocks catalog", () => {
  test("every catalog block has a statically generated page", () => {
    const page = readFileSync(PAGE, "utf-8");
    expect(page).toContain("return blockStaticParams();");
    const params = blockStaticParams().map((param) => param.name);
    expect(params).toEqual(blocks.map((block) => block.name));
    expect(new Set(params).size).toBe(params.length);
    for (const name of params) {
      expect(getBlock(name)?.name).toBe(name);
      expect(blockPath(name)).toBe(`/blocks/${name}`);
    }
  });

  test("every block has a known category and links to blocks that exist", () => {
    expect(blocks.length).toBeGreaterThan(0);
    for (const block of blocks) {
      expect(blockCategories).toContain(block.category);
      const linked = [...block.requires, ...block.integrates].filter(
        (name) => name !== "*",
      );
      for (const name of linked) {
        expect(getBlock(name), `${block.name}: ${name}`).toBeDefined();
      }
      expect(block.docs).toMatch(/^\/docs\//);
    }
  });

  test("every category has at least one block", () => {
    for (const category of blockCategories) {
      expect(blocks.some((block) => block.category === category)).toBe(true);
    }
  });

  test("the config snippet lists the dependencies before the block", () => {
    const comments = getBlock("comments");
    expect(comments).toBeDefined();
    if (!comments) {
      return;
    }
    const snippet = configSnippet(comments, [
      "updated-at",
      "tenant",
      "access",
      "comments",
    ]);
    expect(snippet).toContain('"updated-at": {},');
    expect(snippet.indexOf("access: {}")).toBeLessThan(
      snippet.indexOf('comments: { mode: "managed" }'),
    );
  });
});

describe("filterBlocks", () => {
  const summaries = blockSummaries();

  test("returns every block for All and an empty query", () => {
    expect(filterBlocks(summaries, ALL_CATEGORIES, "")).toHaveLength(
      summaries.length,
    );
  });

  test("narrows to one category", () => {
    const ai = filterBlocks(summaries, "AI", "");
    expect(ai.length).toBeGreaterThan(0);
    expect(ai.every((block) => block.category === "AI")).toBe(true);
  });

  test("matches every word of the query against name, title and description", () => {
    const found = filterBlocks(summaries, ALL_CATEGORIES, "COMMENTS replies");
    expect(found.map((block) => block.name)).toContain("comments");
    expect(
      filterBlocks(summaries, ALL_CATEGORIES, "zzz-no-such-block"),
    ).toEqual([]);
  });
});
