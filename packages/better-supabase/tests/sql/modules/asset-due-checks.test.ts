import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

const sql = (): string =>
  renderBlocks(["assets"])
    .filter((file) => file.module === "assets")
    .map((file) => file.contents)
    .join("\n");

describe("asset due checks", () => {
  it("keeps the meter decrease warning and adds a service-plan interval", () => {
    const rendered = sql();

    expect(rendered).toContain("ASSET_METER_DECREASE_REASON");
    expect(rendered).toContain("IMPORT_SERIES_DECREASE");
    expect(rendered).toContain("asset_due_checks");
    expect(rendered).toContain('"interval_days"');
    expect(rendered).toContain(
      'new."next_due_at" := new."last_done_at" + make_interval(days => new."interval_days")',
    );
    expect(rendered).toContain("import_due_check");
    expect(rendered).toContain("due_check_updated_at");
  });
});
