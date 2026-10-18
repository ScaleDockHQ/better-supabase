import { describe, expect, test } from "vitest";

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
  test("finds nothing between equal designs, whatever the key order", () => {
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

  test("marks added tables and optional columns as safe", () => {
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

  test("marks drops, renames, type changes and new required columns as breaking", () => {
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

  test("names a table with the same definition a rename", () => {
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

  test("a required column with a default or an identity is safe", () => {
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

  test("an id type change and other table settings", () => {
    expect(
      kinds(projects, {
        projects: { ...projects["projects"], id: "bigint", comment: "Work." },
      }),
    ).toEqual(["table.id projects !", "table.changed projects"]);
  });

  test("keepMissing leaves out the tables the new design doesn't name", () => {
    expect(
      diffAppTables(
        { ...projects, tasks: {} },
        { tasks: { columns: { title: { type: "text" } } } },
        { keepMissing: true },
      ).map((change) => change.kind),
    ).toEqual(["column.added"]);
  });

  test("every breaking change has steps and every safe one has none", () => {
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
