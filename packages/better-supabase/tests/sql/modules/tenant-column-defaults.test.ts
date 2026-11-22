import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

const text = (
  names: string[],
  layout: Parameters<typeof renderBlocks>[1],
): string =>
  renderBlocks(names, layout)
    .map((file) => file.contents)
    .join("\n");

describe("sql.tenantColumn as the default tenant column", () => {
  it("is the tenant column of a data-lifecycle table that names none", () => {
    const sql = text(["data-lifecycle"], {
      modules: {
        "data-lifecycle": {
          options: { tables: { "public.notes": { purge: false } } },
        },
      },
      blockTenantColumn: "workspace_id",
    });

    expect(sql).toContain("workspace_id");
  });

  it("is the auto-table tenant column", () => {
    const sql = text(["data-lifecycle"], {
      modules: { "data-lifecycle": { options: { autoTables: {} } } },
      blockTenantColumn: "workspace_id",
    });

    expect(sql).toContain("workspace_id");
  });
});
