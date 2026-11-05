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

describe("authorOf avatar path", () => {
  it("carries the Storage path when the lookup returns one", () => {
    expect(
      authorOf({
        id: "u1",
        name: "Ada",
        avatarUrl: null,
        avatarPath: "a/1.png",
      }),
    ).toEqual({
      id: "u1",
      name: "Ada",
      avatarUrl: undefined,
      avatarPath: "a/1.png",
    });
  });
});
