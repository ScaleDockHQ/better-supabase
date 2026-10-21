import { describe, expect, it } from "vitest";

import type { AppTablesConfig } from "../../src/config/types/app-tables.ts";

import { diffAppTables, diffDesigns } from "../../src/preset/design-diff.ts";

const projects: AppTablesConfig = {
  projects: {
    columns: {
      name: { type: "text", nullable: false },
      budget: { type: "bigint", format: "currency" },
      notes: { type: "text" },
    },
  },
};

const kinds = (before: AppTablesConfig, after: AppTablesConfig): string[] =>
  diffAppTables(before, after).map(
    (change) =>
      `${change.kind} ${change.table}${change.column === undefined ? "" : `.${change.column}`}${change.breaking ? " !" : ""}`,
  );

describe("diffAppTables", () => {
  it("finds nothing between equal designs, whatever the key order", () => {
    expect(
      diffAppTables(projects, {
        projects: {
          columns: {
            notes: { type: "text" },
            budget: { format: "currency", type: "bigint" },
            name: { nullable: false, type: "text" },
          },
        },
      }),
    ).toEqual([]);
  });

  it("marks added tables and optional columns as safe", () => {
    expect(
      kinds(projects, {
        projects: {
          columns: {
            ...projects["projects"]?.columns,
            due: { type: "date" },
            status: { type: "text", nullable: false, default: "'open'" },
          },
        },
        tasks: { columns: { title: { type: "text" } } },
      }),
    ).toEqual([
      "column.added projects.due",
      "column.added projects.status",
      "table.added tasks",
    ]);
  });

  it("marks drops, renames, type changes and new required columns as breaking", () => {
    const changes = kinds(projects, {
      items: {
        columns: {
          title: { type: "text", nullable: false },
          budget: { type: "numeric" },
          notes: { type: "text", nullable: false },
          owner_id: { type: "uuid", nullable: false },
        },
      },
    });

    expect(changes).toEqual(["table.dropped projects !", "table.added items"]);

    expect(
      kinds(projects, {
        projects: {
          columns: {
            title: { type: "text", nullable: false },
            budget: { type: "numeric" },
            notes: { type: "text", nullable: false },
            owner_id: { type: "uuid", nullable: false },
          },
        },
      }),
    ).toEqual([
      "column.renamed projects.title !",
      "column.type projects.budget !",
      "column.required projects.notes !",
      "column.added projects.owner_id !",
    ]);
  });

  it("names a table with the same definition a rename", () => {
    const [change] = diffAppTables(projects, {
      boards: projects["projects"] ?? {},
    });

    expect(change).toMatchObject({
      kind: "table.renamed",
      table: "boards",
      from: "projects",
      breaking: true,
    });
    expect(change?.steps).toHaveLength(3);
  });

  it("a required column with a default or an identity is safe", () => {
    expect(
      kinds(projects, {
        projects: {
          columns: {
            ...projects["projects"]?.columns,
            notes: { type: "text", nullable: false, default: "''" },
            number: { type: "bigint", nullable: false, identity: true },
          },
        },
      }),
    ).toEqual([
      "column.changed projects.notes",
      "column.added projects.number",
    ]);
  });

  it("an id type change and other table settings", () => {
    expect(
      kinds(projects, {
        projects: { ...projects["projects"], id: "bigint", comment: "Work." },
      }),
    ).toEqual(["table.id projects !", "table.changed projects"]);
  });

  it("adding or dropping a rollup or lookup is safe", () => {
    const counted: AppTablesConfig = {
      projects: {
        ...projects["projects"],
        rollups: {
          task_count: { table: "tasks", via: "project_id", aggregate: "count" },
        },
      },
    };

    expect(kinds(projects, counted)).toEqual(["table.computed projects"]);
    expect(kinds(counted, projects)).toEqual(["table.computed projects"]);
  });

  it("turning events on or off is safe", () => {
    const emitting: AppTablesConfig = {
      projects: { ...projects["projects"], events: true },
    };

    expect(kinds(projects, emitting)).toEqual(["table.events projects"]);
    expect(kinds(emitting, projects)).toEqual(["table.events projects"]);
  });

  it("keeping versions or changing their columns is safe", () => {
    const versioned: AppTablesConfig = {
      projects: {
        ...projects["projects"],
        subject: { type: "project", versions: true },
      },
    };

    const subject: AppTablesConfig = {
      projects: { ...projects["projects"], subject: { type: "project" } },
    };

    expect(kinds(subject, versioned)).toEqual(["table.versions projects"]);
    expect(kinds(versioned, subject)).toEqual(["table.versions projects"]);
  });

  it("a new or tighter column constraint is breaking", () => {
    const status: AppTablesConfig = {
      tasks: {
        columns: {
          status: { type: "text", options: ["open", "done", "archived"] },
          points: { type: "integer", min: 0, max: 10 },
          email: { type: "text" },
          project_id: { type: "uuid", references: { table: "projects" } },
        },
      },
    };

    expect(
      kinds(status, {
        tasks: {
          columns: {
            status: { type: "text", options: ["open", "done"], unique: true },
            points: { type: "integer", min: 1, max: 5 },
            email: { type: "text", format: "email" },
            project_id: { type: "uuid", references: { table: "boards" } },
          },
        },
      }),
    ).toEqual([
      "column.unique tasks.status !",
      "column.options tasks.status !",
      "column.bounds tasks.points !",
      "column.format tasks.email !",
      "column.reference tasks.project_id !",
    ]);
  });

  it("tighter column access is breaking and looser access is safe", () => {
    const columns = (
      notes: "read" | "server" | undefined,
      title: "read" | "server" | undefined,
    ): AppTablesConfig => ({
      tasks: {
        columns: {
          notes: { type: "text", ...(notes ? { access: notes } : {}) },
          title: { type: "text", ...(title ? { access: title } : {}) },
        },
      },
    });

    expect(
      kinds(columns(undefined, "read"), columns("read", "server")),
    ).toEqual(["column.access tasks.notes !", "column.access tasks.title !"]);
    expect(
      kinds(columns("server", "read"), columns(undefined, "read")),
    ).toEqual(["column.changed tasks.notes"]);
  });

  it("a looser constraint, a display format and onDelete are safe", () => {
    const before: AppTablesConfig = {
      tasks: {
        columns: {
          status: { type: "text", options: ["open"], unique: true },
          points: { type: "integer", min: 1, max: 5 },
          body: { type: "text" },
          project_id: { type: "uuid", references: { table: "projects" } },
        },
      },
    };

    expect(
      kinds(before, {
        tasks: {
          columns: {
            status: { type: "text", options: ["open", "done"] },
            points: { type: "integer", min: 0 },
            body: { type: "text", format: "long_text", comment: "Notes." },
            project_id: {
              type: "uuid",
              references: { table: "projects", onDelete: "cascade" },
            },
          },
        },
      }),
    ).toEqual([
      "column.changed tasks.status",
      "column.changed tasks.points",
      "column.changed tasks.body",
      "column.changed tasks.project_id",
    ]);
  });

  it("a new scope, unique set or removed generated columns is breaking", () => {
    const before: AppTablesConfig = {
      tasks: {
        columns: { title: { type: "text" } },
        subject: { type: "task", rank: true, softDelete: true },
      },
    };

    expect(
      kinds(before, {
        tasks: {
          columns: { title: { type: "text" } },
          scope: "user",
          timestamps: false,
          unique: [["title"]],
          subject: { type: "task" },
        },
      }),
    ).toEqual([
      "table.scope tasks !",
      "table.unique tasks !",
      "table.columns tasks !",
    ]);
  });

  it("indexes, the comment and the subject title are safe", () => {
    expect(
      kinds(projects, {
        projects: {
          ...projects["projects"],
          indexes: [["name"]],
          subject: { type: "project", title: "name" },
        },
      }),
    ).toEqual(["table.changed projects"]);
  });

  it("keepMissing leaves out the tables the new design doesn't name", () => {
    expect(
      diffAppTables(
        { ...projects, tasks: {} },
        { tasks: { columns: { title: { type: "text" } } } },
        { keepMissing: true },
      ).map((change) => change.kind),
    ).toEqual(["column.added"]);
  });

  it("every breaking change has steps and every safe one has none", () => {
    const changes = diffDesigns(
      { appTables: projects },
      { appTables: { other: { columns: { x: { type: "text" } } } } },
    );

    expect(changes.length).toBeGreaterThan(0);

    for (const change of changes) {
      expect(change.steps.length > 0).toBe(change.breaking);
    }
  });
});
