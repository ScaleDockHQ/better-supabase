import { describe, expect, test } from "vitest";

import {
  addTable,
  columnError,
  deleteColumn,
  deleteTable,
  type Design,
  EMPTY_DESIGN,
  editTable,
  renameColumn,
  renameTable,
  setColumn,
  withDesign,
  computedRows,
  fittedRollup,
  lookupSources,
  rollupColumns,
  rollupSources,
  tableWithComputed,
  tableWithoutComputed,
} from "../../src/create/index.ts";
import { encodeDesign } from "../../src/preset/index.ts";
import { presetSchema } from "./schema-fixture";

const { preset, data } = presetSchema("saas");

const linked: Design = addTable(
  addTable(EMPTY_DESIGN, "projects", {
    columns: { name: { type: "text", nullable: false } },
  }),
  "tasks",
  {
    columns: {
      project_id: { type: "uuid", references: { table: "projects" } },
      status: { type: "text", options: ["todo", "done"] },
      effort: { type: "integer" },
    },
  },
);

const computed: Design = editTable(
  editTable(linked, "projects", (table) =>
    tableWithComputed(
      table,
      "done_effort",
      {
        rollup: {
          table: "tasks",
          via: "project_id",
          aggregate: "sum",
          column: "effort",
          where: { column: "status", equals: "done" },
        },
      },
      "done_effort",
    ),
  ),
  "tasks",
  (table) =>
    tableWithComputed(
      table,
      "project_name",
      { lookup: { via: "project_id", column: "name" } },
      "project_name",
    ),
);

describe("sources", () => {
  test("a rollup aggregates the tables that link here, a lookup follows a link", () => {
    const tables = linked.appTables ?? {};

    expect(rollupSources(tables, "projects")).toEqual([
      { table: "tasks", via: "project_id" },
    ]);
    expect(lookupSources(tables, "tasks")).toEqual([
      { via: "project_id", target: "projects" },
    ]);
    expect(rollupSources(tables, "tasks")).toEqual([]);
  });

  test("sum takes numbers, min takes ordered types, count takes no column", () => {
    const tasks = linked.appTables?.["tasks"] ?? {};

    expect(rollupColumns(tasks, "sum")).toEqual(["effort"]);
    expect(rollupColumns(tasks, "min")).toContain("created_at");
    expect(rollupColumns(tasks, "count")).toEqual([]);
  });

  test("an aggregate with no column to read falls back to count", () => {
    expect(
      fittedRollup(
        { tasks: { columns: { project_id: { type: "uuid" } } } },
        { table: "tasks", via: "project_id", aggregate: "sum" },
      ),
    ).toEqual({ table: "tasks", via: "project_id", aggregate: "count" });
  });
});

describe("the design", () => {
  test("encodes, and the node lists the computed rows under the columns", () => {
    expect(() => encodeDesign(computed)).not.toThrow();

    const projects = withDesign(data, computed, preset).tables.find(
      (table) => table.id === "public.projects",
    );

    expect(projects?.computed).toEqual([
      {
        name: "done_effort",
        kind: "rollup",
        label: "sum",
        summary: "sum of tasks.effort where status = done",
      },
    ]);
  });

  test("a computed name is taken for new columns", () => {
    expect(
      columnError(
        computed.appTables?.["projects"] ?? {},
        "done_effort",
        preset,
      ),
    ).toMatch(/already has/u);
  });

  test("renaming a table or column keeps the rollup and lookup pointed at it", () => {
    const renamed = renameColumn(
      renameColumn(
        renameTable(computed, "tasks", "todos"),
        "todos",
        "effort",
        "points",
      ),
      "projects",
      "name",
      "title",
    );

    expect(renamed.appTables?.["projects"]?.rollups?.["done_effort"]).toEqual({
      table: "todos",
      via: "project_id",
      aggregate: "sum",
      column: "points",
      where: { column: "status", equals: "done" },
    });
    expect(renamed.appTables?.["todos"]?.lookups?.["project_name"]).toEqual({
      via: "project_id",
      column: "title",
    });

    const via = renameColumn(computed, "tasks", "project_id", "parent_id");

    expect(via.appTables?.["tasks"]?.lookups?.["project_name"]).toEqual({
      via: "parent_id",
      column: "name",
    });
    expect(via.appTables?.["projects"]?.rollups?.["done_effort"]?.via).toBe(
      "parent_id",
    );
  });

  test("deleting what a rollup or lookup reads drops it", () => {
    const noEffort = deleteColumn(computed, "tasks", "effort");

    expect(noEffort.appTables?.["projects"]?.rollups).toBeUndefined();
    expect(noEffort.appTables?.["tasks"]?.lookups).toBeDefined();

    const noTasks = deleteTable(computed, "tasks");

    expect(noTasks.appTables?.["projects"]?.rollups).toBeUndefined();

    const noOption = setColumn(computed, "tasks", "status", {
      type: "text",
      options: ["todo"],
    });

    expect(noOption.appTables?.["projects"]?.rollups).toBeUndefined();
    expect(() => encodeDesign(noTasks)).not.toThrow();
  });

  test("a rollup renames in place and deletes", () => {
    const projects = computed.appTables?.["projects"] ?? {};
    const rollup = projects.rollups?.["done_effort"];

    if (rollup === undefined) {
      throw new Error("The fixture has a rollup.");
    }

    const renamed = tableWithComputed(
      projects,
      "effort_done",
      { rollup },
      "done_effort",
    );

    expect(Object.keys(renamed.rollups ?? {})).toEqual(["effort_done"]);
    expect(
      tableWithoutComputed(renamed, "effort_done").rollups,
    ).toBeUndefined();
    expect(computedRows(tableWithoutComputed(renamed, "effort_done"))).toEqual(
      [],
    );
  });
});
