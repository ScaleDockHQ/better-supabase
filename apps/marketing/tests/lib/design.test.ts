import { describe, expect, test } from "vitest";

import {
  addTable,
  appTableId,
  columnError,
  connect,
  deleteExtraColumn,
  deleteTable,
  type Design,
  designIssues,
  duplicateTable,
  EMPTY_DESIGN,
  freeTableName,
  identifierError,
  isEmptyDesign,
  moveTables,
  renameColumn,
  renameTable,
  setColumn,
  setExtraColumn,
  singular,
  tidy,
  withDesign,
} from "../../lib/design";
import { presetSchema } from "./schema-fixture";

const { preset, data } = presetSchema("saas");

const projects: Design = addTable(EMPTY_DESIGN, "projects", {
  columns: { title: { type: "text", nullable: false } },
});

describe("names", () => {
  test("checks identifiers", () => {
    expect(identifierError("projects")).toBeUndefined();
    expect(identifierError("")).toBe("Enter a name.");
    expect(identifierError("Projects")).toMatch(/lower-case/u);
    expect(identifierError("a".repeat(64))).toMatch(/63/u);
  });

  test("finds a free table name", () => {
    expect(freeTableName(EMPTY_DESIGN, new Set())).toBe("items");
    expect(
      freeTableName(
        addTable(EMPTY_DESIGN, "items"),
        new Set([appTableId("items_2")]),
      ),
    ).toBe("items_3");
  });

  test("refuses columns the table already has", () => {
    const table = projects.appTables?.["projects"] ?? {};

    expect(columnError(table, "title", preset)).toMatch(/already has/u);
    expect(columnError(table, "organization_id", preset)).toMatch(
      /already has/u,
    );
    expect(columnError(table, "created_at", preset)).toMatch(/already has/u);
    expect(columnError(table, "body", preset)).toBeUndefined();
  });

  test("makes table names singular", () => {
    expect(singular("organizations")).toBe("organization");
    expect(singular("categories")).toBe("category");
    expect(singular("status")).toBe("status");
  });
});

describe("edits", () => {
  test("deleting a table drops the columns that reference it", () => {
    const linked = setColumn(
      addTable(projects, "tasks"),
      "tasks",
      "project_id",
      { type: "uuid", references: { table: "projects" } },
    );

    const next = deleteTable(linked, "projects");

    expect(next.appTables?.["projects"]).toBeUndefined();
    expect(next.appTables?.["tasks"]?.columns).toEqual({});
  });

  test("renaming a table follows its references and position", () => {
    const linked = moveTables(
      setColumn(addTable(projects, "tasks"), "tasks", "project_id", {
        type: "uuid",
        references: { table: "projects", onDelete: "cascade" },
      }),
      { [appTableId("projects")]: [10, 20] },
    );

    const next = renameTable(linked, "projects", "boards");

    expect(Object.keys(next.appTables ?? {})).toEqual(["boards", "tasks"]);
    expect(
      next.appTables?.["tasks"]?.columns?.["project_id"]?.references,
    ).toEqual({ table: "boards", onDelete: "cascade" });
    expect(next.positions).toEqual({ [appTableId("boards")]: [10, 20] });
  });

  test("renaming a column keeps its place", () => {
    const two = setColumn(projects, "projects", "body", { type: "text" });

    expect(
      Object.keys(
        renameColumn(two, "projects", "title", "name").appTables?.["projects"]
          ?.columns ?? {},
      ),
    ).toEqual(["name", "body"]);
  });

  test("duplicating a table copies it next to the original", () => {
    const placed = moveTables(projects, { [appTableId("projects")]: [0, 0] });
    const { design, name } = duplicateTable(placed, "projects", new Set());

    expect(name).toBe("projects_copy");
    expect(design.appTables?.["projects_copy"]).toEqual(
      design.appTables?.["projects"],
    );
    expect(design.positions?.[appTableId("projects_copy")]).toEqual([40, 40]);
  });

  test("extra columns come and go per module", () => {
    const one = setExtraColumn(EMPTY_DESIGN, "tenant", "plan", "text");

    expect(one.extraColumns).toEqual({ tenant: { plan: "text" } });
    expect(isEmptyDesign(deleteExtraColumn(one, "tenant", "plan"))).toBe(true);
  });

  test("tidy drops every position", () => {
    expect(
      tidy(moveTables(projects, { [appTableId("projects")]: [1, 2] }))
        .positions,
    ).toBeUndefined();
  });
});

describe("connect", () => {
  const merged = withDesign(data, projects, preset);

  const blockTable = data.tables.find(
    (table) => data.blockTables[table.id] !== undefined,
  );

  test("adds a nullable cascading key to a block table", () => {
    expect(blockTable).toBeDefined();

    const target = blockTable?.id ?? "";

    const result = connect(projects, merged, preset, {
      source: appTableId("projects"),
      target,
    });

    if (!result.ok) {
      throw new Error(result.error);
    }

    const column =
      result.design.appTables?.["projects"]?.columns?.[result.column];

    expect(column?.nullable).toBe(true);
    expect(column?.references).toEqual({
      ...data.blockTables[target],
      onDelete: "cascade",
    });
  });

  test("adds a key to another app table", () => {
    const two = addTable(projects, "tasks");

    const result = connect(two, withDesign(data, two, preset), preset, {
      source: appTableId("tasks"),
      target: appTableId("projects"),
    });

    expect(result).toMatchObject({ ok: true, column: "project_id" });
  });

  test("refuses block tables as the source, self references and duplicates", () => {
    expect(
      connect(projects, merged, preset, {
        source: blockTable?.id ?? "",
        target: appTableId("projects"),
      }),
    ).toMatchObject({ ok: false });

    expect(
      connect(projects, merged, preset, {
        source: appTableId("projects"),
        target: appTableId("projects"),
      }),
    ).toMatchObject({ ok: false });

    expect(
      connect(projects, merged, preset, {
        source: appTableId("projects"),
        target: data.tenantTable ?? "",
      }),
    ).toMatchObject({ ok: false, error: expect.stringMatching(/already/u) });
  });
});

describe("withDesign", () => {
  test("adds app tables with their implicit columns and scope key", () => {
    const merged = withDesign(data, projects, preset);

    const table = merged.tables.find(
      (each) => each.id === appTableId("projects"),
    );

    expect(table?.columns.map((column) => column.name)).toEqual([
      "id",
      "organization_id",
      "title",
      "created_at",
      "updated_at",
    ]);
    expect(table?.foreignKeys[0]?.target).toMatchObject({
      schema: "better_supabase",
      table: "organizations",
    });
    expect(merged.manifests[appTableId("projects")]).toBe("app-tables");
  });

  test("appends extra columns to the tables that take them", () => {
    const [id] = data.extraColumns;
    const table = data.tables.find((each) => each.id === id);

    expect(table).toBeDefined();

    const merged = withDesign(
      data,
      setExtraColumn(EMPTY_DESIGN, table?.module ?? "", "nickname", "text"),
      preset,
    );

    expect(
      merged.tables
        .find((each) => each.id === id)
        ?.columns.some((column) => column.name === "nickname"),
    ).toBe(true);
  });
});

describe("designIssues", () => {
  test("is empty for a valid design", () => {
    expect(designIssues(projects, data)).toEqual([]);
  });

  test("flags clashes, missing references, set null on required columns and orphan extra columns", () => {
    const blockName = data.tables[0]?.name ?? "";

    const design = setExtraColumn(
      setColumn(addTable(projects, blockName), "projects", "board_id", {
        type: "uuid",
        nullable: false,
        references: { table: "boards", onDelete: "set null" },
      }),
      "not-a-block",
      "x",
      "text",
    );

    expect(designIssues(design, data).map((issue) => issue.table)).toEqual([
      "projects",
      "projects",
      blockName,
      "not-a-block",
    ]);
  });
});
