import { describe, expect, it } from "vitest";

import { withBlockSubjects } from "../../src/config/block-subjects.ts";
import { renderBlocks } from "../../src/sql/index.ts";

const historySql = (names: string[]) =>
  renderBlocks(names, { subjects: withBlockSubjects({}, names, {}) })
    .filter((file) => file.module === "field-history")
    .map((file) => file.contents)
    .join("\n");

describe("subject.history on block entities", () => {
  it("watches the declared columns without an entry in field-history.on", () => {
    const sql = historySql(["field-history", "tasks"]);

    expect(sql).toContain("bsb_field_history_task");
    expect(sql).toMatch(/after update of "?title"?, "?body"?/u);
  });

  it("adds no trigger when the entity's block is not installed", () => {
    expect(historySql(["field-history"])).not.toContain(
      "bsb_field_history_task",
    );
  });
});
