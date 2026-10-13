import { describe, expect, it } from "vitest";

import { parseCsv, toCsv } from "../../src/core/csv.ts";

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
