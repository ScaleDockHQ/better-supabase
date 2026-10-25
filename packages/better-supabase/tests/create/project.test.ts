import { describe, expect, it } from "vitest";

import type { Issue, Project } from "../../src/create/index.ts";

import { checkProject, loadProject } from "../../src/create/index.ts";

const design = {
  appTables: {
    tasks: { columns: { title: { type: "text", nullable: false } } },
  },
};

async function projectOf(input: unknown): Promise<Project> {
  const loaded = await loadProject(input);

  if (!loaded.ok) {
    throw new Error(JSON.stringify(loaded.issues));
  }

  return loaded.project;
}

async function issuesOf(input: unknown): Promise<readonly Issue[]> {
  const loaded = await loadProject(input);

  return loaded.ok ? [] : loaded.issues;
}

describe("loadProject", () => {
  it("reads a design object with the preset inside it", async () => {
    const project = await projectOf({ ...design, preset: "saas" });

    expect(project.preset.tenantName).toBe("organization");
    expect(project.files.some((file) => file.contents.includes("tasks"))).toBe(
      true,
    );
  });

  it("reports a bad design as issues instead of throwing", async () => {
    const [first] = await issuesOf({ appTables: { "Bad Name": {} } });

    expect(first).toMatchObject({ severity: "error", source: "design" });
  });

  it("reports an unreadable design code as an issue", async () => {
    expect(await issuesOf("not a design")).toMatchObject([
      { code: "invalid_code" },
    ]);
  });
});

describe("checkProject", () => {
  it("returns no issues for a project that can be written", async () => {
    const project = await projectOf({ ...design, preset: "saas" });

    expect(await checkProject(project)).toEqual([]);
  });

  it("adds the issues the sql option finds", async () => {
    const project = await projectOf({ ...design, preset: "saas" });

    const issues = await checkProject(project, {
      sql: async () => [
        {
          code: "sql_error",
          severity: "error",
          source: "sql",
          path: "",
          table: "organizations",
          file: "a.sql",
          message: "boom",
        },
      ],
    });

    expect(issues).toHaveLength(1);
    expect(issues[0]?.source).toBe("sql");
  });

  it("flags a table name a block already uses", async () => {
    const issues = await issuesOf({
      appTables: { organizations: { columns: {} } },
      preset: "saas",
    });

    expect(issues.map((each) => each.code)).toContain("table_name_taken");
  });
});
