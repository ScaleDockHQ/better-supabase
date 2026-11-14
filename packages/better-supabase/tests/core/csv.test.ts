import { describe, expect, it } from "vitest";

import { csvHeader, csvLines, parseCsv, toCsv } from "../../src/core/csv.ts";

describe("parseCsv", () => {
  it("reads the RFC 4180 quoted example", () => {
    expect(parseCsv('"aaa","b""bb","ccc"\r\nzzz,yyy,xxx\r\n')).toEqual([
      ["aaa", 'b"bb', "ccc"],
      ["zzz", "yyy", "xxx"],
    ]);
  });

  it("keeps a comma and a line break inside quotes", () => {
    expect(parseCsv('"a,b","c\r\nd"\r\n')).toEqual([["a,b", "c\r\nd"]]);
  });

  it("round-trips rows that toCsv writes", () => {
    const csv = toCsv([{ name: "Ada", note: 'say "hi"' }]);
    const [header, row] = parseCsv(csv);
    expect(header).toEqual(["name", "note"]);
    expect(row).toEqual(["Ada", 'say "hi"']);
  });
});

describe("csvHeader and csvLines", () => {
  it("write the header and the rows apart, escaping formulas by default", () => {
    const rows = [{ a: "=1", b: "x" }];

    expect(csvHeader(["a", "b"])).toBe("a,b\r\n");
    expect(csvLines(rows, ["a", "b"])).toBe("'=1,x\r\n");
    expect(csvLines(rows, ["a", "b"], false)).toBe("=1,x\r\n");
  });
});
