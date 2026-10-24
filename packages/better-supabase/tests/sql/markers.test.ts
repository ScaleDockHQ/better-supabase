import { describe, expect, it } from "vitest";

import {
  blockFileState,
  entitiesMarker,
  entityMarkers,
  isModuleDataFile,
  moduleFileVersion,
  withBlockHash,
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
    const line = entitiesMarker("tasks", [
      { key: "work_item", singular: "task", plural: "tasks" },
    ]);

    expect(line).toBe("-- @bsb-names tasks work_item=task/tasks");
    expect(
      entityMarkers(`${line!}\n-- @bs-entities parties party=contact/contacts`),
    ).toEqual(
      new Map([
        ["tasks", "work_item=task/tasks"],
        ["parties", "party=contact/contacts"],
      ]),
    );
  });
});

describe("block file hashes", () => {
  const file =
    "-- header\n-- @bsb-block tags@3 managed\n\ncreate table t ();\n";

  it("adds the hash line under the block marker, once", () => {
    const hashed = withBlockHash(file);

    expect(hashed).toMatch(
      /^-- header\n-- @bsb-block tags@3 managed\n-- @bsb-hash sha256:[0-9a-f]{64}\n\ncreate table t \(\);\n$/,
    );
    expect(withBlockHash(hashed)).toBe(hashed);
  });

  it("tells a clean file from one without a hash and one edited by hand", () => {
    const hashed = withBlockHash(file);

    expect(blockFileState(hashed)).toBe("clean");
    expect(blockFileState(file)).toBe("missing");
    expect(blockFileState(hashed.replace("t ()", "t (id int)"))).toBe("edited");
  });

  it("ignores header edits above the body", () => {
    const hashed = withBlockHash(file);

    expect(blockFileState(hashed.replace("-- header", "-- other"))).toBe(
      "clean",
    );
  });
});
