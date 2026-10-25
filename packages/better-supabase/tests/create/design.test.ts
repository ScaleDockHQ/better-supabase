import { describe, expect, it } from "vitest";

import type { Design } from "../../src/create/index.ts";

import {
  boundError,
  fitted,
  optionError,
  addTable,
  appTableId,
  columnError,
  connect,
  deleteColumn,
  deleteExtraColumn,
  defaultError,
  deleteTable,
  designIssues,
  duplicateTable,
  EMPTY_DESIGN,
  freeTableName,
  identifierError,
  isEmptyDesign,
  moveTables,
  referenceFrom,
  renameColumn,
  renameTable,
  subjectTypeError,
  setColumn,
  setExtraColumn,
  setTableId,
  singular,
  tidy,
  updateTable,
  userConnection,
  withDesign,
} from "../../src/create/index.ts";
import { presetSchema } from "./schema-fixture";

const { preset, data } = presetSchema("saas");

const projects: Design = addTable(EMPTY_DESIGN, "projects", {
  columns: { title: { type: "text", nullable: false } },
});

describe("names", () => {
  it("checks identifiers", () => {
    expect(identifierError("projects")).toBeUndefined();
    expect(identifierError("")).toBe("Enter a name.");
    expect(identifierError("Projects")).toMatch(/lower-case/u);
    expect(identifierError("a".repeat(59))).toMatch(/58/u);
    expect(identifierError("pg_things")).toMatch(/pg_/u);
  });

  it("finds a free table name", () => {
    expect(freeTableName(EMPTY_DESIGN, new Set())).toBe("items");
    expect(
      freeTableName(
        addTable(EMPTY_DESIGN, "items"),
        new Set([appTableId("items_2")]),
      ),
    ).toBe("items_3");
  });

  it("refuses columns the table already has", () => {
    const table = projects.appTables?.["projects"] ?? {};

    expect(columnError(table, "title", preset)).toMatch(/already has/u);
    expect(columnError(table, "organization_id", preset)).toMatch(
      /already has/u,
    );
    expect(columnError(table, "created_at", preset)).toMatch(/already has/u);
    expect(columnError(table, "body", preset)).toBeUndefined();
    expect(columnError(table, "user_id", preset)).toMatch(/scope/u);
  });

  it("makes table names singular", () => {
    expect(singular("organizations")).toBe("organization");
    expect(singular("categories")).toBe("category");
    expect(singular("status")).toBe("status");
  });
});

describe("edits", () => {
  it("deleting a table drops the columns that reference it", () => {
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

  it("deleting a table drops its references from unique and index sets", () => {
    const linked = updateTable(
      setColumn(
        setColumn(addTable(projects, "tasks"), "tasks", "title", {
          type: "text",
        }),
        "tasks",
        "project_id",
        { type: "uuid", references: { table: "projects" } },
      ),
      "tasks",
      {
        unique: [["project_id", "title"], ["project_id"]],
        indexes: [["project_id"]],
      },
    );

    const tasks = deleteTable(linked, "projects").appTables?.["tasks"];

    expect(tasks?.unique).toEqual([["title"]]);
    expect(tasks?.indexes).toBeUndefined();
  });

  it("checks defaults against options and bounds", () => {
    expect(
      defaultError({ type: "text", options: ["open"] }, "'open'"),
    ).toBeUndefined();
    expect(
      defaultError({ type: "text", options: ["open"] }, "'closed'"),
    ).toBeDefined();
    expect(defaultError({ type: "integer", min: 1 }, "0")).toBeDefined();
    expect(defaultError({ type: "integer" }, "")).toBeUndefined();
  });

  it("refuses a subject type another table uses", () => {
    const design = updateTable(projects, "projects", {
      subject: { type: "project" },
    });

    expect(subjectTypeError(design, "projects", "project")).toBeUndefined();
    expect(subjectTypeError(design, "tasks", "project")).toMatch(/projects/u);
    expect(subjectTypeError(design, "tasks", "Task")).toBeDefined();
  });

  it("renaming a table follows its references and position", () => {
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

  it("renaming a column keeps its place", () => {
    const two = setColumn(projects, "projects", "body", { type: "text" });

    expect(
      Object.keys(
        renameColumn(two, "projects", "title", "name").appTables?.["projects"]
          ?.columns ?? {},
      ),
    ).toEqual(["name", "body"]);
  });

  it("duplicating a table copies it next to the original", () => {
    const placed = moveTables(projects, { [appTableId("projects")]: [0, 0] });
    const { design, name } = duplicateTable(placed, "projects", new Set());

    expect(name).toBe("projects_copy");
    expect(design.appTables?.["projects_copy"]).toEqual(
      design.appTables?.["projects"],
    );
    expect(design.positions?.[appTableId("projects_copy")]).toEqual([40, 40]);
  });

  it("extra columns come and go per module", () => {
    const one = setExtraColumn(EMPTY_DESIGN, "tenant", "plan", "text");

    expect(one.extraColumns).toEqual({ tenant: { plan: "text" } });
    expect(isEmptyDesign(deleteExtraColumn(one, "tenant", "plan"))).toBe(true);
  });

  it("tidy drops every position", () => {
    expect(
      tidy(moveTables(projects, { [appTableId("projects")]: [1, 2] }))
        .positions,
    ).toBeUndefined();
  });
});

describe("connect", () => {
  const merged = withDesign(data, projects, preset);

  const blockTable = data.tables.find(
    (table) =>
      data.blockTables[table.id] !== undefined &&
      table.primaryKey.length === 1 &&
      table.columns.find((column) => column.name === table.primaryKey[0])
        ?.type === "uuid",
  );

  it("adds a nullable cascading key to a block table", () => {
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

  it("adds a key to another app table", () => {
    const two = addTable(projects, "tasks");

    const result = connect(two, withDesign(data, two, preset), preset, {
      source: appTableId("tasks"),
      target: appTableId("projects"),
    });

    expect(result).toMatchObject({ ok: true, column: "project_id" });

    if (!result.ok) {
      throw new Error(result.error);
    }

    expect(
      userConnection(result.design, appTableId("tasks"), "project_id"),
    ).toEqual({ table: "tasks", column: "project_id" });
    expect(
      userConnection(result.design, appTableId("projects"), "title"),
    ).toBeUndefined();
    expect(
      userConnection(result.design, "better_supabase.members", "user_id"),
    ).toBeUndefined();
  });

  it("a self reference is parent_id and sets null on delete", () => {
    const result = connect(projects, merged, preset, {
      source: appTableId("projects"),
      target: appTableId("projects"),
    });

    if (!result.ok) {
      throw new Error(result.error);
    }

    expect(result.column).toBe("parent_id");
    expect(
      result.design.appTables?.["projects"]?.columns?.["parent_id"]?.references,
    ).toEqual({ table: "projects", onDelete: "set null" });
  });

  it("a second reference to the same table gets a free role name", () => {
    const two = addTable(projects, "tasks");
    const target = appTableId("projects");

    const first = connect(two, withDesign(data, two, preset), preset, {
      source: appTableId("tasks"),
      target,
    });

    if (!first.ok) {
      throw new Error(first.error);
    }

    const second = connect(
      first.design,
      withDesign(data, first.design, preset),
      preset,
      { source: appTableId("tasks"), target },
    );

    expect(second).toMatchObject({ ok: true, column: "project_2_id" });
  });

  it("a reference to auth.users never takes the reserved user_id", () => {
    const first = connect(projects, merged, preset, {
      source: appTableId("projects"),
      target: "auth.users",
    });

    if (!first.ok) {
      throw new Error(first.error);
    }

    expect(first.column).toBe("owner_id");

    const second = connect(
      first.design,
      withDesign(data, first.design, preset),
      preset,
      { source: appTableId("projects"), target: "auth.users" },
    );

    expect(second).toMatchObject({ ok: true, column: "assignee_id" });
  });

  it("refuses block tables as the source and the tenant table", () => {
    expect(
      connect(projects, merged, preset, {
        source: blockTable?.id ?? "",
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

  describe("referenceFrom", () => {
    it("adds the key to a table the schema doesn't have yet", () => {
      const target = appTableId("projects");
      const merged = withDesign(data, projects, preset);
      const added = addTable(projects, "tasks", {});

      const result = referenceFrom(added, merged, preset, "tasks", target);

      if (!result.ok) {
        throw new Error(result.error);
      }

      expect(result.column).toBe("project_id");
      expect(
        result.design.appTables?.["tasks"]?.columns?.["project_id"]?.references,
      ).toMatchObject({ table: "projects", onDelete: "cascade" });
    });

    it("refuses a table that isn't in the design", () => {
      const result = referenceFrom(projects, data, preset, "tasks", "x.y");

      expect(result.ok).toBe(false);
    });
  });
});

describe("withDesign", () => {
  it("adds app tables with their implicit columns and scope key", () => {
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

  it("appends extra columns to the tables that take them", () => {
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
  it("is empty for a valid design", () => {
    expect(designIssues(projects, data, preset)).toEqual([]);
  });

  it("flags clashes, missing references, set null on required columns and orphan extra columns", () => {
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

    expect(
      designIssues(design, data, preset).map((issue) => issue.table),
    ).toEqual(["projects", "projects", blockName, "not-a-block"]);
  });

  it("flags a required column members can't write that has no default", () => {
    const locked = setColumn(projects, "projects", "internal_notes", {
      type: "text",
      nullable: false,
      access: "server",
    });

    expect(
      designIssues(locked, data, preset).map((issue) => issue.message),
    ).toEqual([
      "projects.internal_notes is required, and signed-in users can't write it, so give it a default.",
    ]);

    const defaulted = setColumn(projects, "projects", "internal_notes", {
      type: "text",
      nullable: false,
      default: "''",
      access: "server",
    });

    expect(designIssues(defaulted, data, preset)).toEqual([]);
  });

  it("flags duplicate subject types and names Postgres would truncate", () => {
    const design = updateTable(
      updateTable(addTable(projects, "boards"), "boards", {
        subject: { type: "item" },
      }),
      "projects",
      { subject: { type: "item" } },
    );

    expect(designIssues(design, data, preset).length).toBeGreaterThan(0);

    const long = setColumn(projects, "projects", "x".repeat(50), {
      type: "text",
      options: ["a"],
    });

    expect(
      designIssues(long, data, preset).some((issue) =>
        /63/u.test(issue.message),
      ),
    ).toBe(true);
  });
});

describe("column keys", () => {
  it("fitted drops the keys a type can't take", () => {
    expect(
      fitted({
        type: "integer",
        format: "email",
        options: ["a"],
        min: 1.5,
        max: 5,
        identity: true,
        default: "0",
        nullable: true,
      }),
    ).toEqual({ type: "integer", max: 5, identity: true });

    expect(
      fitted({ type: "text", format: "email", min: -1, max: 200 }),
    ).toEqual({ type: "text", format: "email", max: 200 });

    expect(fitted({ type: "text", encrypted: true })).toEqual({
      type: "text",
      encrypted: true,
    });
    expect(fitted({ type: "text[]", encrypted: true })).toEqual({
      type: "text[]",
    });
    expect(fitted({ type: "text", unique: true, encrypted: true })).toEqual({
      type: "text",
      unique: true,
    });
    expect(
      fitted({
        type: "uuid",
        references: { table: "projects" },
        encrypted: true,
      }),
    ).toEqual({ type: "uuid", references: { table: "projects" } });
    expect(fitted({ type: "bigint", identity: true, encrypted: true })).toEqual(
      { type: "bigint", identity: true },
    );
  });

  it("checks options and bounds", () => {
    expect(optionError(["a"], "a")).toMatch(/already/u);
    expect(optionError([], "")).toMatch(/Enter/u);
    expect(optionError([], "b\tc")).toMatch(/tabs/u);
    expect(optionError([], "b")).toBeUndefined();

    expect(boundError({ type: "integer" }, "min", "1.5")).toMatch(/whole/u);
    expect(boundError({ type: "text" }, "max", "-1")).toMatch(/length/u);
    expect(boundError({ type: "numeric", max: 1 }, "min", "2")).toMatch(
      /at or below/u,
    );
    expect(boundError({ type: "numeric" }, "min", "")).toBeUndefined();
  });

  it("renaming and deleting a column updates the composite keys", () => {
    const keyed = updateTable(
      setColumn(projects, "projects", "code", { type: "text" }),
      "projects",
      { unique: [["title", "code"]], indexes: [["code"]] },
    );

    const renamed = renameColumn(keyed, "projects", "code", "slug");

    expect(renamed.appTables?.["projects"]?.unique).toEqual([
      ["title", "slug"],
    ]);
    expect(renamed.appTables?.["projects"]?.indexes).toEqual([["slug"]]);

    const deleted = deleteColumn(renamed, "projects", "slug");

    expect(deleted.appTables?.["projects"]?.unique).toEqual([["title"]]);
    expect(deleted.appTables?.["projects"]?.indexes).toBeUndefined();
  });

  it("updateTable removes a key set to undefined", () => {
    const commented = updateTable(projects, "projects", {
      comment: "A project",
    });

    expect(commented.appTables?.["projects"]?.comment).toBe("A project");
    expect(
      updateTable(commented, "projects", { comment: undefined }).appTables?.[
        "projects"
      ],
    ).not.toHaveProperty("comment");
  });

  it("a bigint id retypes the columns that reference the table", () => {
    const linked = setColumn(
      addTable(projects, "tasks"),
      "tasks",
      "project_id",
      {
        type: "uuid",
        default: "gen_random_uuid()",
        references: { table: "projects" },
      },
    );

    const next = setTableId(linked, "projects", "bigint");

    expect(next.appTables?.["projects"]?.id).toBe("bigint");
    expect(next.appTables?.["tasks"]?.columns?.["project_id"]).toEqual({
      type: "bigint",
      references: { table: "projects" },
    });

    const merged = withDesign(data, next, preset);

    const id = merged.tables
      .find((table) => table.id === appTableId("projects"))
      ?.columns.find((column) => column.name === "id");

    expect(id).toMatchObject({ type: "bigint", default: "identity" });
    expect(
      setTableId(next, "projects", "uuid").appTables?.["projects"],
    ).not.toHaveProperty("id");
  });

  it("designIssues flags a composite key on a missing column", () => {
    const design = updateTable(projects, "projects", {
      unique: [["title", "missing"]],
    });

    expect(designIssues(design, data, preset)).toMatchObject([
      {
        code: "unknown_column",
        path: "/appTables/projects/unique/0",
        table: "projects",
        message: expect.stringMatching(/missing/u),
      },
    ]);
  });
});
