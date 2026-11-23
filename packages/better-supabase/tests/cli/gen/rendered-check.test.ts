import { describe, expect, it } from "vitest";

import {
  checkInstalledModules,
  checkRenderedModules,
} from "../../../src/cli/gen/rendered-check.ts";
import { resolveConfig } from "../../../src/config/index.ts";

const file = (contents: string, module = "tasks") => ({
  module,
  kind: "schema" as const,
  path: `supabase/schemas/${module}.sql`,
  contents,
});

describe("checkRenderedModules", () => {
  it("accepts SQL that parses", async () => {
    await expect(
      checkRenderedModules([file("create table a (id int);\n")]),
    ).resolves.toBeUndefined();
  });

  it("names the module, the position and the statement that does not parse", async () => {
    const result = await checkRenderedModules([
      file(
        "create table a (id int);\ncreate table b (\n  id int,\n);\nselect 1;\n",
      ),
    ]);

    expect(result?.code).toBe(1);
    expect(result?.error).toContain("module tasks");
    expect(result?.error).toContain("supabase/schemas/tasks.sql:");
    expect(result?.error).toContain("create table b (");
    expect(result?.error).not.toContain("create table a");
  });

  it("names the instance when a module installs under another name", async () => {
    const result = await checkRenderedModules([
      { ...file("select from from;", "tasks"), instance: "chores" },
    ]);

    expect(result?.error).toContain("module chores");
  });
});

describe("checkInstalledModules", () => {
  it("accepts the modules of a config", async () => {
    await expect(
      checkInstalledModules(resolveConfig({ blocks: ["tasks"] }, "/project")),
    ).resolves.toBeUndefined();
  });
});
