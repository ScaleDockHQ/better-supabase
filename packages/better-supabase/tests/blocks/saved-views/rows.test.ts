import { describe, expect, it } from "vitest";

import { viewOf } from "../../../src/blocks/saved-views/index.ts";

describe("viewOf", () => {
  it("parses a list_views row with its preference and fields", () => {
    expect(
      viewOf({
        id: "v1",
        list: "deals",
        scope: "team",
        ownerId: null,
        teamId: "t1",
        name: "Open",
        kind: "board",
        state: { filters: [] },
        rank: "a0",
        isDefault: true,
        preference: { pinned: true },
        fields: { color: "blue" },
      }),
    ).toEqual({
      id: "v1",
      list: "deals",
      scope: "team",
      ownerId: null,
      teamId: "t1",
      name: "Open",
      kind: "board",
      state: { filters: [] },
      rank: "a0",
      isDefault: true,
      preference: { isDefault: false, hidden: false, pinned: true },
      fields: { color: "blue" },
    });
  });

  it("falls back for unknown values and rejects a non-object", () => {
    expect(
      viewOf({ id: "v2", list: "deals", name: "Mine", scope: "x", kind: "y" }),
    ).toMatchObject({ scope: "user", kind: "table", rank: "V", state: {} });
    expect(() => viewOf("nope")).toThrow(TypeError);
  });
});
