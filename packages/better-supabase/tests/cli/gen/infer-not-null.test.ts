import { describe, expect, it } from "vitest";

import { inferNotNull } from "../../../src/cli/gen/model-functions.ts";

describe("inferNotNull", () => {
  it("treats a coalesce return as not null", () => {
    expect(inferNotNull("begin return coalesce(v, 0); end")).toBe(true);
    expect(inferNotNull("select coalesce(name, '')")).toBe(true);
  });

  it("leaves a plain return and a missing body alone", () => {
    expect(inferNotNull("begin return v_name; end")).toBeUndefined();
    expect(inferNotNull(undefined)).toBeUndefined();
  });

  it("ignores coalesce inside a comment", () => {
    expect(
      inferNotNull("-- return coalesce(v, 0)\nbegin return v; end"),
    ).toBeUndefined();
  });
});
