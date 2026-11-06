import { describe, expect, it } from "vitest";

import { buildModel, conflicts } from "../../../src/sql/pipeline/model.ts";
import {
  BLOCK_OVERLAPS,
  PRELUDE_FUNCTIONS,
} from "../../../src/sql/pipeline/prelude.ts";
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

  it("shares no object between two block files except the listed overlaps", () => {
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

    expect(shared.toSorted()).toEqual([...BLOCK_OVERLAPS].toSorted());
  });

  it("keeps the overlap list free of objects the blocks no longer share", () => {
    for (const key of BLOCK_OVERLAPS) {
      expect({ key, count: model.objects.get(key)?.length ?? 0 }).toEqual({
        key,
        count: expect.any(Number),
      });
      expect(model.objects.get(key)?.length ?? 0).toBeGreaterThan(1);
    }
  });
});
