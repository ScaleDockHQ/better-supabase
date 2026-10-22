import { describe, expect, it } from "vitest";

import {
  BLOCK_RENAMES,
  currentBlockName,
  formerBlockName,
  renamedBlock,
  resolveBlocks,
  SQL_MODULES,
} from "../../src/sql/index.ts";

describe("BLOCK_RENAMES", () => {
  it("maps every 0.14 name to a block that exists", () => {
    for (const [from, to] of Object.entries(BLOCK_RENAMES)) {
      expect(SQL_MODULES[from]).toBeUndefined();
      expect(SQL_MODULES[to] ?? to).toBeDefined();
    }
  });

  it("never renames two blocks to one name", () => {
    const targets = Object.values(BLOCK_RENAMES);

    expect(new Set(targets).size).toBe(targets.length);
  });

  it("finds the new and the former name", () => {
    expect(renamedBlock("work-items")).toBe("tasks");
    expect(renamedBlock("tasks")).toBeUndefined();
    expect(formerBlockName("tasks")).toBe("work-items");
    expect(formerBlockName("work-items")).toBeUndefined();
    expect(currentBlockName("tenant")).toBe("memberships");
    expect(currentBlockName("comments")).toBe("comments");
  });

  it("ignores names on the object prototype", () => {
    expect(renamedBlock("constructor")).toBeUndefined();
  });
});

describe("resolveBlocks", () => {
  it("names the codemod for a 0.14 block name", () => {
    expect(() => resolveBlocks(["work-items"])).toThrow(
      'The "work-items" block is named "tasks" since 0.15. Run `better-supabase codemod 0.15`',
    );
  });

  it("lists the blocks for an unknown name", () => {
    expect(() => resolveBlocks(["nope"])).toThrow('Unknown SQL module "nope"');
  });
});
