import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

describe("field seal", () => {
  it("leaves a value that already has the prefix", () => {
    const sql = renderBlocks(["field-encryption"])
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain(
      "left(field_seal.value, 5) = 'bsf1:' then field_seal.value",
    );
  });
});
