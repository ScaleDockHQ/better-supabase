import { describe, expect, it } from "vitest";

import {
  creditorReference,
  referencePayload,
} from "../../src/blocks/banking/references.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";

describe("ISO 11649 creditor references", () => {
  it("pins the 2009 edition", () => {
    expect(SPEC_PINS.iso11649).toBe("2009");
  });

  it("computes the check digits of the standard's example", () => {
    expect(creditorReference("5390 0754 7034")).toBe("RF18539007547034");
    expect(referencePayload("RF18 5390 0754 7034")).toBe("539007547034");
  });

  it("rejects a reference whose check digits are wrong", () => {
    expect(referencePayload("RF19539007547034")).toBeUndefined();
  });

  it("refuses a payload longer than 21 characters", () => {
    expect(() => creditorReference("A".repeat(22))).toThrow(RangeError);
  });
});
