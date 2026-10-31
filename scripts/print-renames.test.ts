import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { entityKeyTable, tableRenameTable } from "./print-renames.ts";

const guide = readFileSync(
  join(
    import.meta.dirname,
    "../apps/docs/content/docs/(docs)/migration/0.46-to-0.47.mdx",
  ),
  "utf-8",
);

describe("print-renames", () => {
  it("prints the entity key table the guide shows", () => {
    expect(guide).toContain(entityKeyTable());
  });

  it("prints the table name table the guide shows", () => {
    expect(guide).toContain(tableRenameTable());
  });
});
