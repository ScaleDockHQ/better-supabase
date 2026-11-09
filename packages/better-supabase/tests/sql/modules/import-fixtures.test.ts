import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

describe("import run fixtures", () => {
  it("creates a run, ages it, touches subjects and checks dispatch arms", () => {
    const sql = renderBlocks(["pgtap"])
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain("tests.import_run_fixture");
    expect(sql).toContain("tests.age_import_run");
    expect(sql).toContain("tests.bulk_touch_subjects");
    expect(sql).toContain("tests.assert_override_dispatches_all");
    expect(sql).toContain("missing dispatch arms");
  });
});
