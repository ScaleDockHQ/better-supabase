import { describe, expect, it } from "vitest";

import { exampleChartFormat } from "../src/chart-format.ts";

describe("chart format", () => {
  it("targets API version 1 and has a key", () => {
    expect(exampleChartFormat.apiVersion).toBe(1);
    expect(exampleChartFormat.key).toBe("example-chart");
  });

  it("parses rows, parents first, and skips comments", async () => {
    const accounts = await exampleChartFormat.parse(
      "# code;name;type;parent\n1000;Assets;asset;\n1100;Bank;asset;1000\n",
    );

    expect(accounts).toEqual([
      { code: "1000", name: "Assets", type: "asset" },
      { code: "1100", name: "Bank", type: "asset", parentCode: "1000" },
    ]);
  });

  it("throws on a row it cannot read instead of returning half a chart", async () => {
    await expect(
      Promise.resolve().then(() =>
        exampleChartFormat.parse("1000;Assets;nope;"),
      ),
    ).rejects.toThrow(/bad chart row/);
  });
});
