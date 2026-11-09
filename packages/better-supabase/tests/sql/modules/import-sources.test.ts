import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

describe("import sources", () => {
  it("lists registered sources and every run of the tenant", () => {
    const sql = renderBlocks(["imports"])
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain("import_sources");
    expect(sql).toContain("list_import_source_runs");
    expect(sql).toContain('r."tenant_id" = list_import_source_runs.tenant');
    expect(sql).not.toContain("created_by = auth.uid()");
  });
});
