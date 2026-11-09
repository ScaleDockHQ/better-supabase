import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

const clone = (layout: Parameters<typeof renderBlocks>[1]): string =>
  renderBlocks(["tasks", "tags"], layout)
    .filter((file) => file.contents.includes("clone_task"))
    .map((file) => file.contents)
    .join("\n");

describe("clone_task and the tags block", () => {
  it("copies taggings when the tags block has the table", () => {
    expect(clone({})).toContain("taggings");
  });

  it("leaves taggings out when the app turned the table off", () => {
    const sql = clone({ modules: { tags: { tables: { taggings: null } } } });

    expect(sql).toContain("clone_task");
    expect(sql).not.toContain("taggings");
  });
});
