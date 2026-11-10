import { describe, expect, it } from "vitest";

import {
  camelOf,
  exportedNames,
  usedImport,
} from "../../../src/cli/gen/renamed-blocks.ts";

describe("renamed block modules", () => {
  it("keeps only the imported names a module's lines use", () => {
    const text = usedImport({
      importSpecifiers: [
        "  DefaultTaskConfig as taskConfig,",
        "  DefaultTaskPermissions,",
        "  unusedThing as other,",
      ],
      subpath: "better-supabase/blocks/tasks",
      lines: [
        "export const a = taskConfig;",
        "export const b = DefaultTaskPermissions;",
      ],
    });

    expect(text).toContain("taskConfig,");
    expect(text).toContain("DefaultTaskPermissions");
    expect(text).not.toContain("other");
    expect(text).toContain('from "better-supabase/blocks/tasks"');
  });

  it("lists the names a module exports", () => {
    expect(
      exportedNames([
        "export const taskConfig = 1;\nexport declare type TaskRow = {};",
        "export interface TaskInput {}",
        "const hidden = 1;",
      ]),
    ).toEqual(["taskConfig", "TaskRow", "TaskInput"]);
  });

  it("writes a hyphenated instance name in camel case", () => {
    expect(camelOf("time-entries")).toBe("timeEntries");
    expect(camelOf("tasks")).toBe("tasks");
  });
});
