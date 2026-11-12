import { describe, expect, it } from "vitest";

import { moneyText } from "@/components/record-list/money-text";

describe("moneyText", () => {
  it("formats minor units in the page's locale", () => {
    expect(moneyText({ amount: "123456", currency: "EUR" }, "en")).toBe(
      "€1,234.56",
    );
    expect(moneyText({ amount: "123456", currency: "EUR" }, "nl")).toMatch(
      /1\.234,56/u,
    );
  });

  it("is empty for a missing or malformed value", () => {
    expect(moneyText(null, "en")).toBe("");
    expect(moneyText("12", "en")).toBe("");
    expect(moneyText({ amount: 12, currency: "EUR" } as never, "en")).toBe("");
  });
});
