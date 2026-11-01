import { describe, expect, it } from "vitest";

import { decodeRead } from "../../src/core/read-type.ts";
import { DEAL_BOARD_RESULT } from "../../src/sql/modules/deals-reads.ts";

describe("decodeRead", () => {
  it("returns a value that matches the type", () => {
    const value = { pipelineId: "p", stages: [], weighted: [] };

    expect(decodeRead(DEAL_BOARD_RESULT, value, "deal_board")).toEqual(value);
  });

  it("names the path that differs", () => {
    expect(() =>
      decodeRead(
        DEAL_BOARD_RESULT,
        { pipelineId: "p", stages: [{ id: 1 }], weighted: [] },
        "deal_board",
      ),
    ).toThrow(/deal_board\.stages\[0\]\.id is number, expected text/);
  });

  it("fills nullable keys with null and rejects a missing required one", () => {
    expect(decodeRead(["text?"], [null, "a"], "x")).toEqual([null, "a"]);
    expect(() => decodeRead({ a: "bool" }, {}, "x")).toThrow(/x\.a/);
  });
});
