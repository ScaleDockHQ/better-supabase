import { describe, expect, it } from "vitest";

import { authorOf } from "../../src/core/block-authors.ts";

describe("authorOf", () => {
  it("reads the id, name and avatar", () => {
    expect(
      authorOf({ id: "u1", name: "Ada", avatarUrl: "https://a.test/ada.png" }),
    ).toEqual({ id: "u1", name: "Ada", avatarUrl: "https://a.test/ada.png" });
  });

  it("leaves a missing name or avatar undefined", () => {
    expect(authorOf({ id: "u1", name: null, avatarUrl: null })).toEqual({
      id: "u1",
      name: undefined,
      avatarUrl: undefined,
    });
  });

  it("returns undefined without an author object", () => {
    expect(authorOf(undefined)).toBeUndefined();
    expect(authorOf(null)).toBeUndefined();
    expect(authorOf({ name: "Ada" })).toBeUndefined();
  });
});
