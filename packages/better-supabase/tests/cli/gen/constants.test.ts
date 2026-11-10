import { describe, expect, it } from "vitest";

import type { Model } from "../../../src/cli/gen/model.ts";

import { emitConstants } from "../../../src/cli/gen/constants.ts";

// SAFETY: emitConstants reads only these three arrays.
const empty = { enums: [], tables: [], functions: [] } as unknown as Model;

describe("gen constants", () => {
  it("writes empty modules for a project without enums or tables", () => {
    const files = emitConstants(empty, "generated.ts");

    expect(files.map((file) => file.path)).toEqual(["enums.ts", "columns.ts"]);
    expect(files[0]?.contents).toContain("export {};");
    expect(files[1]?.contents).toContain("export {};");
  });

  it("puts the files next to a nested output", () => {
    expect(
      emitConstants(empty, "src/db/generated.ts").map((f) => f.path),
    ).toEqual(["src/db/enums.ts", "src/db/columns.ts"]);
  });

  it("refuses two lists that export the same name", () => {
    const list = (name: string) => ({
      schema: "public",
      name,
      key: name,
      constant: "kindValues",
      typeName: "Kind",
      values: ["a"],
    });

    const model = {
      enums: [list("one"), list("two")],
      tables: [],
      functions: [],
    } as unknown as Model;

    expect(() => emitConstants(model, "generated.ts")).toThrow(/both export/u);
  });
});
