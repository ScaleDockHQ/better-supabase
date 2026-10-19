import {
  addTable,
  appTableId,
  designIssues,
  withDesign,
} from "better-supabase/create";
import { describe, expect, test } from "vitest";

import { manyToMany } from "../../lib/relations";
import { presetSchema } from "./schema-fixture";

const { preset, data } = presetSchema("saas");

const base = addTable(addTable({}, "projects"), "labels");
const drawn = withDesign(data, base, preset);
const taken = new Set(drawn.tables.map((table) => table.id));

describe("manyToMany", () => {
  test("adds a junction table with a cascading reference to each side", () => {
    const result = manyToMany(
      base,
      drawn,
      preset,
      "projects",
      appTableId("labels"),
      taken,
      [40, 80],
    );

    if (!result.ok) {
      throw new Error(result.error);
    }

    expect(result.name).toBe("projects_labels");
    expect(result.design.appTables?.["projects_labels"]).toEqual({
      unique: [["project_id", "label_id"]],
      columns: {
        project_id: {
          type: "uuid",
          nullable: false,
          references: { table: "projects", onDelete: "cascade" },
        },
        label_id: {
          type: "uuid",
          nullable: false,
          references: { table: "labels", onDelete: "cascade" },
        },
      },
    });
    expect(result.design.positions?.[appTableId("projects_labels")]).toEqual([
      40, 80,
    ]);
    expect(designIssues(result.design, drawn, preset)).toEqual([]);
  });

  test("links users and keeps the source table's scope", () => {
    const design = addTable({}, "projects", { scope: "none" });

    const result = manyToMany(
      design,
      withDesign(data, design, preset),
      preset,
      "projects",
      "auth.users",
      taken,
    );

    expect(result).toMatchObject({ ok: true, name: "projects_users" });
    expect(
      result.ok ? result.design.appTables?.["projects_users"] : undefined,
    ).toMatchObject({
      scope: "none",
      unique: [["project_id", "member_id"]],
      columns: {
        member_id: {
          nullable: false,
          references: { table: "auth.users", onDelete: "cascade" },
        },
      },
    });
  });

  test("refuses a link to the table itself", () => {
    expect(
      manyToMany(
        base,
        drawn,
        preset,
        "projects",
        appTableId("projects"),
        taken,
      ),
    ).toMatchObject({ ok: false });
  });
});
