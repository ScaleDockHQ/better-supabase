import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

import { BLOCK_CATALOG } from "../packages/better-supabase/src/preset/block-catalog.generated.ts";
import { categoryFile, outputs } from "./build-skill-references.ts";

describe("the skill block references", () => {
  const files = outputs();

  it("matches the files on disk", () => {
    for (const [file, contents] of files) {
      expect(readFileSync(file, "utf-8")).toBe(contents);
    }
  });

  it("writes one file per category", () => {
    for (const category of BLOCK_CATALOG.categories) {
      expect(
        [...files.keys()].some((file) => file.endsWith(categoryFile(category))),
      ).toBe(true);
    }
  });

  it("lists every block exactly once", () => {
    const text = [...files.values()].join("\n");

    for (const block of BLOCK_CATALOG.blocks) {
      expect(text.split(`\n## ${block.name}\n`)).toHaveLength(2);
    }
  });
});
