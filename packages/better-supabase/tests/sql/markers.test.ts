import { describe, expect, it } from "vitest";

import {
  entitiesMarker,
  entityMarkers,
  isModuleDataFile,
  moduleFileVersion,
} from "../../src/sql/markers.ts";

describe("block file markers", () => {
  it("reads the @bsb-block line and the @bs-module line of 0.14 files", () => {
    expect(moduleFileVersion("-- x\n-- @bsb-block tags@3 managed\n")).toEqual({
      module: "tags",
      version: 3,
    });
    expect(moduleFileVersion("-- x\n-- @bs-module tags@2 adopt\n")).toEqual({
      module: "tags",
      version: 2,
    });
  });

  it("recognizes data files in both forms", () => {
    expect(isModuleDataFile("-- @bsb-block-data tags\n")).toBe(true);
    expect(isModuleDataFile("-- @bs-module-data tags\n")).toBe(true);
    expect(isModuleDataFile("-- @bsb-block tags@1 managed\n")).toBe(false);
  });

  it("writes @bsb-names and reads both forms of the names line", () => {
    const line = entitiesMarker("work-items", [
      { key: "work_item", singular: "task", plural: "tasks" },
    ]);

    expect(line).toBe("-- @bsb-names work-items work_item=task/tasks");
    expect(
      entityMarkers(`${line!}\n-- @bs-entities parties party=contact/contacts`),
    ).toEqual(
      new Map([
        ["work-items", "work_item=task/tasks"],
        ["parties", "party=contact/contacts"],
      ]),
    );
  });
});
