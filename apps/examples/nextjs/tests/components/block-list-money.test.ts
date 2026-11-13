import { describe, expect, it } from "vitest";

import type { BlockColumn } from "@/components/record-list/block-list-view";

import { moneyText, withMoneyCells } from "@/components/record-list/money-text";

const COLUMNS: readonly BlockColumn[] = [
  { key: "name", header: "Name", kind: "text" },
  { key: "amount", header: "Amount", kind: "money" },
];

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

describe("withMoneyCells", () => {
  it("formats the money columns and keeps the other cells", () => {
    expect(
      withMoneyCells(
        { id: "1", name: "Plan", amount: { amount: "500", currency: "EUR" } },
        COLUMNS,
        "en",
      ),
    ).toEqual({ id: "1", name: "Plan", amount: "€5.00" });
  });
});
