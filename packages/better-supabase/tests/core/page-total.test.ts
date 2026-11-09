import { describe, expect, it } from "vitest";

import { formatPageTotal } from "../../src/core/page-total.ts";

describe("formatPageTotal", () => {
  it("formats an exact total with the locale's grouping", () => {
    expect(formatPageTotal({ total: 12_300 }, { locale: "en-US" })).toBe(
      "12,300",
    );
    expect(
      formatPageTotal({ total: 12_300, capped: false }, { locale: "de" }),
    ).toBe("12.300");
  });

  it("marks a capped total as an estimate, in your own words if asked", () => {
    expect(
      formatPageTotal({ total: 12_300, capped: true }, { locale: "en-US" }),
    ).toBe("~12,300");
    expect(
      formatPageTotal(
        { total: 12_300, capped: true },
        { locale: "nl", capped: (n) => `ongeveer ${n}` },
      ),
    ).toBe("ongeveer 12.300");
  });

  it("is empty without a total", () => {
    expect(formatPageTotal({ total: null })).toBe("");
  });
});
