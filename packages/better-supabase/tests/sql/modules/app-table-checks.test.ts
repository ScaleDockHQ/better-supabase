import { describe, expect, it } from "vitest";

import type { AppColumnConfig } from "../../../src/config/types/app-tables.ts";

import {
  constraintChecks,
  sampleValue,
} from "../../../src/sql/modules/app-table-checks.ts";

const required = (column: AppColumnConfig): AppColumnConfig => ({
  nullable: false,
  ...column,
});

describe("constraintChecks", () => {
  it("checks a pattern, options and bounds on the expression", () => {
    expect(constraintChecks({ type: "text", format: "email" }, "v")).toEqual([
      expect.stringMatching(/^v ~\* '/u),
    ]);
    expect(
      constraintChecks({ type: "text[]", options: ["a", "b"] }, "v"),
    ).toEqual(["v <@ array['a', 'b']::text[]"]);
    expect(
      constraintChecks({ type: "text", min: 2, max: 9, options: ["ab"] }, "v"),
    ).toEqual(["v in ('ab')", "char_length(v) >= 2", "char_length(v) <= 9"]);
    expect(constraintChecks({ type: "numeric", min: 0 }, "v")).toEqual([
      "v >= 0",
    ]);
  });
});

describe("sampleValue", () => {
  it("needs no value for a nullable, defaulted or identity column", () => {
    expect(sampleValue({ type: "text" })).toBeNull();
    expect(sampleValue(required({ type: "text", default: "x" }))).toBeNull();
    expect(
      sampleValue(required({ type: "bigint", identity: true })),
    ).toBeNull();
  });

  it("has no literal for a reference", () => {
    expect(
      sampleValue(
        required({ type: "uuid", references: { table: "contacts" } }),
      ),
    ).toBeUndefined();
  });

  it("takes the first option", () => {
    expect(sampleValue(required({ type: "text", options: ["a", "b"] }))).toBe(
      "'a'",
    );
    expect(sampleValue(required({ type: "text[]", options: ["a", "b"] }))).toBe(
      "array['a']::text[]",
    );
  });

  it("meets the format and the lower bound", () => {
    expect(sampleValue(required({ type: "text", format: "email" }))).toBe(
      "'test@example.com'",
    );
    expect(sampleValue(required({ type: "text", format: "url" }))).toBe(
      "'https://example.com'",
    );
    expect(sampleValue(required({ type: "text", min: 3 }))).toBe(
      "repeat('x', 3)",
    );
    expect(sampleValue(required({ type: "text" }))).toBe("repeat('x', 1)");
    expect(sampleValue(required({ type: "integer", min: 5 }))).toBe("5");
    expect(sampleValue(required({ type: "numeric" }))).toBe("0");
  });

  it("has a literal for every other type", () => {
    expect(sampleValue(required({ type: "uuid" }))).toBe("gen_random_uuid()");
    expect(sampleValue(required({ type: "boolean" }))).toBe("false");
    expect(sampleValue(required({ type: "timestamptz" }))).toBe("now()");
    expect(sampleValue(required({ type: "date" }))).toBe("current_date");
    expect(sampleValue(required({ type: "jsonb" }))).toBe("'{}'::jsonb");
    expect(sampleValue(required({ type: "text[]" }))).toBe("array[]::text[]");
  });
});
