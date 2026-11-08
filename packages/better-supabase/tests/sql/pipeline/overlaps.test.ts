import { describe, expect, it } from "vitest";

import { buildModel, conflicts } from "../../../src/sql/pipeline/model.ts";
import { PRELUDE_FUNCTIONS } from "../../../src/sql/pipeline/prelude.ts";
import { SQL_MODULES } from "../../../src/sql/registry.ts";
import { renderBlocks } from "../../../src/sql/render.ts";

const files = renderBlocks(Object.keys(SQL_MODULES), {}).filter(
  (file) => file.kind === "schema",
);

const model = buildModel(
  files.map((file) => ({ path: file.path, text: file.contents })),
);

describe("one definition per object", () => {
  it("defines each prelude function once, in the prelude", () => {
    for (const name of PRELUDE_FUNCTIONS) {
      const holders = files
        .filter((file) =>
          new RegExp(
            String.raw`create or replace function "?better_supabase"?\."?${name}"?\(`,
          ).test(file.contents),
        )
        .map((file) => file.module);

      expect({ name, holders }).toEqual({ name, holders: ["prelude"] });
    }
  });

  it("shares no object between two block files", () => {
    const shared = conflicts(model)
      .filter(({ declarations }) => {
        const first = declarations[0]!;

        return (
          first.kind !== "extension" &&
          first.kind !== "schema" &&
          new Set(declarations.map((each) => each.file)).size > 1
        );
      })
      .map(({ key }) => key);

    expect(shared).toEqual([]);
  });
});
