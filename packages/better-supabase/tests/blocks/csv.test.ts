import { describe, expect, it } from "vitest";

import { csvColumns, toCsv } from "../../src/blocks/csv.ts";

describe("toCsv", () => {
  it("quotes, joins nested values as JSON and keeps the column order", () => {
    const rows = [
      { a: "plain", b: 'say "hi"', c: null },
      { b: "line\nbreak", d: { x: 1 }, a: 2n, e: true },
    ];
    expect(csvColumns(rows)).toEqual(["a", "b", "c", "d", "e"]);
    expect(toCsv(rows)).toBe(
      'a,b,c,d,e\r\nplain,"say ""hi""",,,\r\n2,"line\nbreak",,"{""x"":1}",true\r\n',
    );
    expect(toCsv([], { columns: ["only"] })).toBe("only\r\n");
  });

  it("escapes cells a spreadsheet would run as formulas unless told not to", () => {
    const rows = [{ v: "=SUM(A1)" }, { v: "-5" }, { v: -5 }, { v: "@x" }];
    expect(toCsv(rows)).toBe("v\r\n'=SUM(A1)\r\n'-5\r\n-5\r\n'@x\r\n");
    expect(toCsv(rows, { escapeFormulas: false })).toBe(
      "v\r\n=SUM(A1)\r\n-5\r\n-5\r\n@x\r\n",
    );
  });
});
