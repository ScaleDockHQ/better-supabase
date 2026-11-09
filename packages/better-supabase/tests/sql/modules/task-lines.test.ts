import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

const sql = (
  extra: readonly string[] = [],
  layout: Parameters<typeof renderBlocks>[1] = {},
): string =>
  renderBlocks(["tasks", ...extra], layout)
    .filter((file) => file.module === "tasks")
    .map((file) => file.contents)
    .join("\n");

describe("task specification and material lines", () => {
  it("orders specification lines and material lines and keeps estimated minutes", () => {
    const rendered = sql();

    expect(rendered).toContain("task_specification_lines");
    expect(rendered).toContain("task_material_lines");
    expect(rendered).toContain('"description"');
    expect(rendered).toContain('"quantity"');
    expect(rendered).toContain('"unit"');
    expect(rendered).toContain('"estimate"');
    expect(rendered).toContain('"variant_id"');
    expect(rendered).toContain('"rank"');
    expect(rendered).toContain('"estimated_minutes" integer');
    expect(rendered).toContain('order by y."rank"');
  });

  it("maps the minutes column and the specification description", () => {
    const rendered = sql([], {
      modules: {
        tasks: {
          columns: {
            items: { estimatedMinutes: "minutes" },
            specification: { description: "spec" },
          },
        },
      },
    });

    expect(rendered).toContain('"minutes" integer');
    expect(rendered).not.toContain('"estimated_minutes"');
    expect(rendered).toContain('"spec" text not null');
  });

  it("leaves the lines out when the app maps the tables to null", () => {
    const rendered = sql([], {
      modules: { tasks: { tables: { specification: null, materials: null } } },
    });

    expect(rendered).not.toContain("task_specification_lines");
    expect(rendered).not.toContain("task_material_lines");
    expect(rendered).toContain('"estimated_minutes"');
  });

  it("links a material line to a catalog variant", () => {
    const rendered = sql(["catalog"]);

    expect(rendered).toContain("references");
    expect(rendered).toContain("product_variants");
  });
});
