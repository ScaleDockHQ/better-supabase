import { describe, expect, it } from "vitest";

import { toCamel, toSnake } from "../../src/casing/index.ts";

describe("toCamel", () => {
  it("camel-cases snake names and keeps leading underscores", () => {
    expect(toCamel("first_name")).toBe("firstName");
    expect(toCamel("address__2")).toBe("address2");
    expect(toCamel("_internal_id")).toBe("_internalId");
    expect(toCamel("__meta")).toBe("__meta");
    expect(toCamel("firstName")).toBe("firstName");
  });

  it("round-trips through toSnake", () => {
    for (const name of ["first_name", "_internal_id", "customer_tags"])
      expect(toSnake(toCamel(name))).toBe(name);
  });
});
