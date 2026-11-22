import { describe, expect, it } from "vitest";

import {
  settleGroups,
  topLevelValue,
  withoutConfigPaths,
} from "../../src/cli/codemod-prune.ts";

const CONFIG = `export default defineConfig({
  blocks: {
    memberships: {
      columns: {
        memberships: {
          lastUsedAt: "last_used_at",
          role: "team_role",
        },
      },
      options: { roleThrough: "x" },
    },
    tags: { columns: { tags: { rank: null } } },
  },
});
`;

describe("withoutConfigPaths", () => {
  it("removes an entry and keeps the others", () => {
    const { text, missed } = withoutConfigPaths(CONFIG, [
      "blocks.memberships.columns.memberships.lastUsedAt",
    ]);

    expect(missed).toEqual([]);
    expect(text).toContain('role: "team_role"');
    expect(text).not.toContain("lastUsedAt");
  });

  it("removes the parents it leaves empty, down to the block entry", () => {
    const { text } = withoutConfigPaths(CONFIG, [
      "blocks.tags.columns.tags.rank",
    ]);

    expect(text).toMatch(/tags: \{\s*\}/);
    expect(text).not.toContain("columns: { tags");
  });

  it("reports a path it cannot find", () => {
    const { text, missed } = withoutConfigPaths(CONFIG, [
      "blocks.memberships.columns.memberships.nope",
    ]);

    expect(text).toBe(CONFIG);
    expect(missed).toEqual(["blocks.memberships.columns.memberships.nope"]);
  });
});

describe("withoutConfigPaths on shapes the text scanner missed", () => {
  it("finds an array path such as sameTenant[1]", () => {
    const { text, missed } = withoutConfigPaths(
      `export default defineConfig({\n  sameTenant: ["a", "b", "c"],\n});\n`,
      ["sameTenant[1]"],
    );

    expect(missed).toEqual([]);
    expect(text).toContain('sameTenant: ["a", "c"]');
  });

  it("ignores a config shape inside a comment or a string", () => {
    const { text, missed } = withoutConfigPaths(
      `// export default defineConfig({ a: 1 })\nconst note = "{ a: 2 }";\nexport default defineConfig({\n  a: 3,\n  b: 4,\n});\n`,
      ["a"],
    );

    expect(missed).toEqual([]);
    expect(text).toContain("// export default defineConfig({ a: 1 })");
    expect(text).toContain('const note = "{ a: 2 }";');
    expect(text).not.toContain("a: 3");
  });

  it("follows a block name in the blocks list", () => {
    const { text, missed } = withoutConfigPaths(
      `export default defineConfig({\n  blocks: ["x", { block: "tags", columns: { tags: { rank: null } } }],\n});\n`,
      ["blocks.tags.columns.tags.rank"],
    );

    expect(missed).toEqual([]);
    expect(text).not.toContain("rank");
  });

  it("removes a property through a shorthand and keeps the file valid", () => {
    const { text, missed } = withoutConfigPaths(
      `const columns = { a: 1, b: 2 };\nexport default defineConfig({\n  blocks: { x: { columns } },\n});\n`,
      ["blocks.x.columns.a"],
    );

    expect(missed).toEqual([]);
    expect(text).toContain("const columns = { b: 2 };");
  });

  it("reports a spread it cannot edit and leaves the file alone", () => {
    const source = `export default defineConfig({\n  blocks: { x: { ...shared } },\n});\n`;
    const { text, missed } = withoutConfigPaths(source, ["blocks.x.a"]);

    expect(text).toBe(source);
    expect(missed).toEqual(["blocks.x.a"]);
  });
});

describe("settleGroups", () => {
  const groups = [
    ["blocks.a", ["blocks.a.x"]],
    ["blocks.b", ["blocks.b.x", "blocks.b.y"]],
    ["blocks.c", ["blocks.c.x"]],
    ["blocks.d", ["blocks.d.x"]],
  ] as const;

  it("keeps every group when the render never changes", async () => {
    const calls: number[] = [];

    const result = await settleGroups(groups, async (paths) => {
      calls.push(paths.length);

      return true;
    });

    expect(result.refused).toEqual([]);
    expect(result.kept).toHaveLength(5);
    expect(calls).toEqual([5]);
  });

  it("refuses only the groups that something still needs", async () => {
    const result = await settleGroups(
      groups,
      async (paths) => !paths.includes("blocks.c.x"),
    );

    expect(result.refused).toEqual(["blocks.c"]);
    expect(result.kept.toSorted()).toEqual([
      "blocks.a.x",
      "blocks.b.x",
      "blocks.b.y",
      "blocks.d.x",
    ]);
  });
});

describe("withoutConfigPaths misses", () => {
  const missed = (text: string, path: string) =>
    withoutConfigPaths(text, [path]).missed;

  it("misses every path without a closed config object", () => {
    expect(missed("const x = 1;\n", "sql.dir")).toEqual(["sql.dir"]);
    expect(missed("export default defineConfig({ sql: {", "sql")).toEqual([
      "sql",
    ]);
  });

  it("misses a path through a listed name, a scalar or an unclosed object", () => {
    expect(
      missed(
        'export default defineConfig({ blocks: ["tags"] });',
        "blocks.tags.columns",
      ),
    ).toEqual(["blocks.tags.columns"]);
    expect(
      missed('export default defineConfig({ sql: "x" });', "sql.dir"),
    ).toEqual(["sql.dir"]);
    expect(
      missed("export default defineConfig({ a: { b: { c: 1 } });", "a.b.c"),
    ).toEqual(["a.b.c"]);
  });

  it("removes a last property on the closing line", () => {
    expect(
      withoutConfigPaths("export default defineConfig({ a: 1, b: 2 })", ["b"])
        .text,
    ).toBe("export default defineConfig({ a: 1})");
  });
});

describe("topLevelValue", () => {
  it("finds the value text of a top-level key", () => {
    const text = 'export default defineConfig({ sql: { dir: "db" } });';
    const range = topLevelValue(text, "sql")!;

    expect(text.slice(range.start, range.end).trim()).toBe('{ dir: "db" }');
    expect(topLevelValue(text, "casing")).toBeUndefined();
    expect(topLevelValue("const x = 1;", "sql")).toBeUndefined();
  });
});

describe("settleGroups with nothing to settle", () => {
  it("renders nothing for no groups", async () => {
    let renders = 0;

    expect(
      await settleGroups([], async () => {
        renders += 1;

        return true;
      }),
    ).toEqual({ kept: [], refused: [] });
    expect(renders).toBe(0);
  });
});
