import { describe, expect, it } from "vitest";

import { withoutConfigPaths } from "../../src/cli/codemod-prune.ts";

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
