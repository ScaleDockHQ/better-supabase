import { describe, expect, it } from "vitest";

import { getArgSource, getArgSqlType } from "../../src/sql/reads.ts";

describe("read argument types", () => {
  it("maps each argument type to its SQL type and its TypeScript type", () => {
    expect(getArgSqlType("id")).toBe("{id}");
    expect(getArgSqlType("text[]")).toBe("text[]");
    expect(getArgSource("int")).toBe("number");
    expect(getArgSource("text[]")).toBe("readonly string[]");
  });
});
