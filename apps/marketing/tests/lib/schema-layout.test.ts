import { describe, expect, test } from "vitest";

import { addTable, isAppTable, withDesign } from "../../lib/design";
import {
  groupId,
  layoutSchema,
  type LayoutOptions,
  NODE_WIDTH,
  roundedPath,
  softColumns,
  tableHeight,
  tableRows,
} from "../../lib/schema-layout";
import { presetSchema } from "./schema-fixture";

const { preset, data } = presetSchema("saas");

const OPTIONS: LayoutOptions = {
  expanded: new Set(),
  softRefs: true,
  collapsed: new Set(),
  isApp: isAppTable,
};

function overlaps(
  a: { x: number; y: number; width: number; height: number },
  b: { x: number; y: number; width: number; height: number },
): boolean {
  return (
    a.x < b.x + b.width &&
    b.x < a.x + a.width &&
    a.y < b.y + b.height &&
    b.y < a.y + a.height
  );
}

describe("tableRows", () => {
  const soft = softColumns(data);

  const wide = data.tables.find(
    (table) =>
      tableRows(table, soft.get(table.id), {
        expanded: false,
        editable: false,
        app: false,
      }).hidden > 0,
  );

  test("hides the plain columns until the table is expanded", () => {
    expect(wide).toBeDefined();

    if (wide === undefined) {
      return;
    }

    const collapsed = tableRows(wide, soft.get(wide.id), {
      expanded: false,
      editable: false,
      app: false,
    });

    const expanded = tableRows(wide, soft.get(wide.id), {
      expanded: true,
      editable: true,
      app: false,
    });

    expect(collapsed.footer).toEqual(["more"]);
    expect(expanded.columns).toHaveLength(wide.columns.length);
    expect(expanded.footer).toEqual(["less", "add"]);
    expect(tableHeight(expanded)).toBeGreaterThan(tableHeight(collapsed));
  });
});

describe("roundedPath", () => {
  test("rounds each corner by at most the radius", () => {
    expect(
      roundedPath([
        { x: 0, y: 0 },
        { x: 100, y: 0 },
        { x: 100, y: 100 },
      ]),
    ).toBe("M 0 0 L 92 0 Q 100 0 100 8 L 100 100");
  });

  test("uses a smaller radius on short segments", () => {
    expect(
      roundedPath([
        { x: 0, y: 0 },
        { x: 4, y: 0 },
        { x: 4, y: 100 },
      ]),
    ).toBe("M 0 0 L 2 0 Q 4 0 4 2 L 4 100");
  });

  test("draws nothing without points", () => {
    expect(roundedPath([])).toBe("");
  });
});

describe("layoutSchema", () => {
  test("places every table once, without overlaps, inside its group", async () => {
    const layout = await layoutSchema(data, OPTIONS);
    const rects = Object.entries(layout.tables);

    expect(rects.map(([id]) => id).toSorted()).toEqual(
      data.tables.map((table) => table.id).toSorted(),
    );

    for (const [index, [id, rect]] of rects.entries()) {
      expect(rect.width).toBe(NODE_WIDTH);

      for (const [other, next] of rects.slice(index + 1)) {
        expect(overlaps(rect, next), `${id} and ${other}`).toBe(false);
      }

      const group = layout.groups.find(
        (each) => each.id === groupId(data.manifests[id] ?? ""),
      );

      if (group === undefined) {
        throw new Error(`${id} is in no group`);
      }

      expect(rect.x).toBeGreaterThanOrEqual(group.x);
      expect(rect.y).toBeGreaterThanOrEqual(group.y);
      expect(rect.x + rect.width).toBeLessThanOrEqual(group.x + group.width);
      expect(rect.y + rect.height).toBeLessThanOrEqual(group.y + group.height);
    }
  });

  test("routes an edge for every relation, soft ones only when asked", async () => {
    const withSoft = await layoutSchema(data, OPTIONS);

    const withoutSoft = await layoutSchema(data, {
      ...OPTIONS,
      softRefs: false,
    });

    expect(withSoft.edges.some((edge) => edge.kind === "soft")).toBe(true);
    expect(withoutSoft.edges.every((edge) => edge.kind === "foreign")).toBe(
      true,
    );
    expect(withSoft.edges.every((edge) => edge.points.length >= 2)).toBe(true);
  });

  test("draws a collapsed group as one node and moves its edges to it", async () => {
    const manifest = data.manifests[data.tables[0]?.id ?? ""] ?? "";

    const layout = await layoutSchema(data, {
      ...OPTIONS,
      collapsed: new Set([manifest]),
    });

    const members = data.tables.filter(
      (table) => data.manifests[table.id] === manifest,
    );

    expect(
      members.every((table) => layout.tables[table.id] === undefined),
    ).toBe(true);
    expect(
      layout.groups.find((group) => group.id === groupId(manifest))?.collapsed,
    ).toBe(true);
  });

  test("lays out app tables and tables outside the schema", async () => {
    const merged = withDesign(data, addTable({}, "projects"), preset);
    const layout = await layoutSchema(merged, OPTIONS);

    expect(layout.tables["public.projects"]).toBeDefined();
    expect(layout.externals["auth.users"]).toBeDefined();
  });

  test("draws only the visible tables", async () => {
    const [first] = data.tables;

    const layout = await layoutSchema(data, {
      ...OPTIONS,
      visible: new Set([first?.id ?? ""]),
    });

    expect(Object.keys(layout.tables)).toEqual([first?.id]);
  });
});
