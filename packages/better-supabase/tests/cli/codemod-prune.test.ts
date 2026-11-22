import { describe, expect, it } from "vitest";

import {
  settleGroups,
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
