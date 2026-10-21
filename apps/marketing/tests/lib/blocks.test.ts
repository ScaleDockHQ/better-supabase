import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { ALL_CATEGORIES, filterBlocks } from "../../lib/block-filter";
import {
  blockCategories,
  blockGraphLayout,
  blockGraphSummary,
  blockPath,
  blocks,
  blockStaticParams,
  blockSummaries,
  type CatalogBlock,
  columnLayout,
  configSnippet,
  getBlock,
} from "../../lib/blocks";

const PAGE = join(
  import.meta.dirname,
  "../../app/(blocks)/blocks/[name]/page.tsx",
);

describe("blocks catalog", () => {
  it("every catalog block has a statically generated page", () => {
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

  it("every block has a known category and links to blocks that exist", () => {
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

  it("every category has at least one block", () => {
    for (const category of blockCategories) {
      expect(blocks.some((block) => block.category === category)).toBe(true);
    }
  });

  it("the config snippet lists the dependencies before the block", () => {
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

function requireBlock(name: string): CatalogBlock {
  const block = getBlock(name);

  if (!block) {
    throw new Error(`No block ${name} in the catalog.`);
  }

  return block;
}

const bare = (
  overrides: Partial<CatalogBlock> & Pick<CatalogBlock, "name">,
): CatalogBlock => ({
  ...requireBlock("comments"),
  requires: [],
  integrates: [],
  ...overrides,
});

describe("blockGraphLayout", () => {
  it("puts requirements left of the block and integrations right of it", () => {
    const block = bare({
      name: "comments",
      requires: ["tenant", "access"],
      integrates: ["notifications"],
    });

    const layout = blockGraphLayout(block);
    const at = (id: string) => layout.nodes.find((node) => node.id === id);
    const center = at("comments");

    expect(center?.focus).toBe(true);
    expect(at("tenant")?.x).toBeLessThan(center?.x ?? 0);
    expect(at("access")?.x).toBe(at("tenant")?.x);
    expect(at("notifications")?.x).toBeGreaterThan(center?.x ?? 0);
    expect(layout.edges).toEqual([
      { from: "comments", to: "tenant", kind: "requires" },
      { from: "comments", to: "access", kind: "requires" },
      { from: "comments", to: "notifications", kind: "integrates" },
    ]);
  });

  it("centers the block on the taller column and keeps every box inside the canvas", () => {
    const layout = blockGraphLayout(
      bare({ name: "comments", requires: ["tenant", "access", "updated-at"] }),
    );

    const center = layout.nodes.find((node) => node.focus);
    const access = layout.nodes.find((node) => node.id === "access");

    expect(center?.y).toBe(access?.y);

    for (const node of layout.nodes) {
      expect(node.x).toBeGreaterThanOrEqual(0);
      expect(node.y).toBeGreaterThanOrEqual(0);
      expect(node.x + layout.nodeWidth).toBeLessThanOrEqual(layout.width);
      expect(node.y + layout.nodeHeight).toBeLessThanOrEqual(layout.height);
    }
  });

  it("sizes the boxes to the longest label", () => {
    const short = blockGraphLayout(
      bare({ name: "comments", requires: ["tenant"] }),
    );

    const long = blockGraphLayout(
      bare({ name: "comments", requires: ["notification-preferences-x"] }),
    );

    expect(long.nodeWidth).toBeGreaterThan(short.nodeWidth);
  });

  it("drops the empty columns of a block with no dependencies", () => {
    const layout = blockGraphLayout(bare({ name: "comments" }));

    expect(layout.nodes).toHaveLength(1);
    expect(layout.edges).toEqual([]);
    expect(layout.width).toBe((layout.nodes[0]?.x ?? 0) * 2 + layout.nodeWidth);
  });

  it("draws the wildcard as an unlinked box and a module in both lists once", () => {
    const layout = blockGraphLayout(
      bare({
        name: "comments",
        requires: ["tenant"],
        integrates: ["tenant", "*"],
      }),
    );

    const wildcard = layout.nodes.find((node) => node.id === "*");

    expect(wildcard).toMatchObject({
      label: "every module",
      category: null,
      href: null,
    });
    expect(layout.nodes.filter((node) => node.id === "tenant")).toHaveLength(1);
    expect(layout.edges.map((edge) => edge.kind)).toEqual([
      "requires",
      "integrates",
    ]);
  });

  it("links every catalog block node to its page, in its category", () => {
    for (const block of blocks) {
      const layout = blockGraphLayout(block);

      for (const node of layout.nodes) {
        if (node.id === "*") {
          continue;
        }

        expect(node.href).toBe(blockPath(node.id));
        expect(node.category).toBe(getBlock(node.id)?.category);
      }
    }
  });
});

describe("columnLayout", () => {
  it("widens the canvas for an edge between two boxes of one column", () => {
    const spec = (id: string) => ({
      id,
      label: id,
      category: "Tenancy & accounts",
      href: null,
      focus: false,
    });

    const flat = columnLayout([[spec("a"), spec("b")]], []);

    const looped = columnLayout(
      [[spec("a"), spec("b")]],
      [{ from: "a", to: "b", kind: "integrates" }],
    );

    expect(looped.width).toBeGreaterThan(flat.width);
  });

  it("drops edges to boxes that are not in the layout", () => {
    const layout = columnLayout(
      [[{ id: "a", label: "a", category: null, href: null, focus: true }]],
      [{ from: "a", to: "missing", kind: "requires" }],
    );

    expect(layout.edges).toEqual([]);
  });
});

describe("blockGraphSummary", () => {
  it("names the requirements and the integrations", () => {
    expect(
      blockGraphSummary(
        bare({
          name: "comments",
          requires: ["tenant", "access"],
          integrates: ["*"],
        }),
      ),
    ).toBe("comments requires tenant and access, and works with every module.");
  });

  it("says so when there are none", () => {
    expect(blockGraphSummary(bare({ name: "comments" }))).toBe(
      "comments has no dependencies.",
    );
  });
});

describe("filterBlocks", () => {
  const summaries = blockSummaries();

  it("returns every block for All and an empty query", () => {
    expect(filterBlocks(summaries, ALL_CATEGORIES, "")).toHaveLength(
      summaries.length,
    );
  });

  it("narrows to one category", () => {
    const ai = filterBlocks(summaries, "AI", "");
    expect(ai.length).toBeGreaterThan(0);
    expect(ai.every((block) => block.category === "AI")).toBe(true);
  });

  it("matches every word of the query against name, title and description", () => {
    const found = filterBlocks(summaries, ALL_CATEGORIES, "COMMENTS replies");
    expect(found.map((block) => block.name)).toContain("comments");
    expect(
      filterBlocks(summaries, ALL_CATEGORIES, "zzz-no-such-block"),
    ).toEqual([]);
  });
});
