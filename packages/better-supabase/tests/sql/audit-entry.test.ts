import { describe, expect, it } from "vitest";

import { castId } from "../../src/sql/modules/audit-entry.ts";

describe("castId", () => {
  it("casts a text expression to each id type, or yields null", () => {
    expect(castId("x", "uuid")).toContain("::uuid");
    expect(castId("x", "bigint")).toContain("::bigint");
    expect(castId("x", "integer")).toContain("::integer");
    expect(castId("x", "text")).toBe("x");
  });
});
