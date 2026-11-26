import { describe, expect, it } from "vitest";

import { defineTags } from "../../src/next/tag-functions.ts";

describe("defineTags", () => {
  const tags = defineTags(["customers", "invoices"]);

  it("names a tenant's entry", () => {
    expect(tags.customers("org-1")).toBe("bsb:customers@org-1");
  });

  it("names the table's own tag without a tenant", () => {
    expect(tags.invoices()).toBe("bsb:invoices");
  });
});
