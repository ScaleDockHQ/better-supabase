import { describe, expect, it } from "vitest";

import type { AppTablesConfig } from "../../src/config/types/app-tables.ts";

import { APP_TABLES_MODULE } from "../../src/sql/modules/app-tables.ts";
import { renderBlocks } from "../../src/sql/render.ts";

const BLOCKS = ["memberships", "organizations", "updated-at"];

const files = (appTables: AppTablesConfig) =>
  renderBlocks(BLOCKS, { appTables }).filter(
    (file) => file.module === APP_TABLES_MODULE,
  );

const PROJECTS: AppTablesConfig = {
  projects: {
    columns: {
      name: { type: "text" },
      budget: { type: "bigint" },
      rate: { type: "bigint" },
    },
    columnGroups: {
      money: { columns: ["budget", "rate"], update: "projects.budget" },
    },
  },
};

describe("appTables columnGroups", () => {
  it("renders a before update trigger that raises 42501", () => {
    const sql = files(PROJECTS)
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain("projects_column_groups");
    expect(sql).toContain("current_user not in ('authenticated', 'anon')");
    expect(sql).toContain('new."budget" is distinct from old."budget"');
    expect(sql).toContain("projects.budget");
    expect(sql).toContain("errcode = '42501'");
    expect(sql).toContain("before update on");
  });

  it("renders nothing without groups", () => {
    const sql = files({ projects: { columns: { name: { type: "text" } } } })
      .map((file) => file.contents)
      .join("\n");

    expect(sql).not.toContain("column_groups");
  });

  it("checks the trigger in the pgTAP file", () => {
    const tests = files(PROJECTS).find((file) => file.kind === "test");

    expect(tests?.contents).toContain("column_groups");
  });

  it("needs a table scoped per tenant", () => {
    expect(() =>
      files({ projects: { ...PROJECTS["projects"]!, scope: "user" } }),
    ).toThrow("columnGroups needs a table scoped per tenant");
  });
});
