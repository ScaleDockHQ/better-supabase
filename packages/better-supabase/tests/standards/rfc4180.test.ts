import { describe, expect, it } from "vitest";

import { parseCsv } from "../../src/core/csv.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";

describe("RFC 4180", () => {
  it("pins the CSV version", () => {
    expect(SPEC_PINS.rfc4180).toBe("2005-10");
  });

  it("reads a quoted field", () => {
    expect(parseCsv('"a,b",c\r\n')).toEqual([["a,b", "c"]]);
  });
});
