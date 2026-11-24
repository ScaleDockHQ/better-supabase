import { describe, expect, it } from "vitest";

import { readArgSource, readArgSqlType } from "../../src/sql/reads.ts";

describe("read argument types", () => {
  it("maps each argument type to its SQL type and its TypeScript type", () => {
    expect(readArgSqlType("id")).toBe("{id}");
    expect(readArgSqlType("text[]")).toBe("text[]");
    expect(readArgSource("int")).toBe("number");
    expect(readArgSource("text[]")).toBe("readonly string[]");
  });
});
