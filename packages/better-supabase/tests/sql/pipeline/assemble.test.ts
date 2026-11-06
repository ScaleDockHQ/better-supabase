import { describe, expect, it } from "vitest";

import {
  dataFileHeader,
  moduleHeader,
  moduleRow,
  testFileHeader,
} from "../../../src/sql/pipeline/assemble.ts";

describe("file headers", () => {
  it("writes the block marker, the description and the notice", () => {
    const header = moduleHeader({
      instance: "tasks",
      version: 4,
      mode: "managed",
      description: "Tasks.",
      block: undefined,
      entities: [],
    });

    expect(header.split("\n")).toStrictEqual([
      "-- better-supabase module: tasks",
      "-- @bsb-block tasks@4 managed",
      "-- Tasks.",
      "-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.",
      "-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.",
    ]);
  });

  it("names the block of a renamed instance and the entity renames", () => {
    const header = moduleHeader({
      instance: "jobs",
      version: 1,
      mode: "custom",
      description: "Tasks.",
      block: "tasks",
      entities: [{ key: "task", singular: "job", plural: "jobs" }],
    });

    expect(header).toContain("-- @bsb-block jobs@1 custom tasks");
    expect(header).toContain("-- @bsb-names jobs task=job/jobs");
  });

  it("writes the data and test headers", () => {
    expect(dataFileHeader("tasks")).toContain("-- @bsb-block-data tasks");
    expect(testFileHeader("tasks")).toContain("-- @bsb-block-test tasks");
  });
});

describe("moduleRow", () => {
  const module = { name: "tasks", version: 3 } as never;

  it("records an own instance by name", () => {
    expect(moduleRow(module, "managed", "tasks")).toContain(
      "values ('tasks', 3, 'managed')",
    );
  });

  it("records the block of a renamed instance", () => {
    const sql = moduleRow(module, "managed", "jobs");

    expect(sql).toContain("values ('jobs', 'tasks', 3, 'managed')");
  });
});
