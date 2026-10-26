import { afterEach, describe, expect, it } from "vitest";

import { isBuildScope, scopeStaticParams } from "../src/build-scope.ts";

const KEY = "BSB_BUILD_SCOPE";
const original = process.env[KEY];

afterEach(() => {
  if (original === undefined) {
    delete process.env[KEY];
  } else {
    process.env[KEY] = original;
  }
});

describe("isBuildScope", () => {
  it("accepts full and minimal", () => {
    expect(isBuildScope("full")).toBe(true);
    expect(isBuildScope("minimal")).toBe(true);
  });

  it("rejects other values", () => {
    expect(isBuildScope(undefined)).toBe(false);
    expect(isBuildScope("")).toBe(false);
    expect(isBuildScope("FULL")).toBe(false);
  });
});

describe("scopeStaticParams", () => {
  const params = [{ id: "1" }, { id: "2" }, { id: "3" }, { id: "4" }];

  it("keeps three entries in a minimal build", () => {
    process.env[KEY] = "minimal";

    expect(scopeStaticParams(params)).toEqual(params.slice(0, 3));
  });

  it("keeps every entry in a full build", () => {
    process.env[KEY] = "full";

    expect(scopeStaticParams(params)).toEqual(params);
  });

  it("keeps every entry when unset", () => {
    delete process.env[KEY];

    expect(scopeStaticParams(params)).toEqual(params);
  });
});
