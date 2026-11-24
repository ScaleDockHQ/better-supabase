import { describe, expect, it } from "vitest";

import { csvField, toCsv } from "@/components/record-list/record-export-button";
import { parseViews } from "@/components/record-list/saved-views";

describe("record list kit", () => {
  it("quotes CSV fields that hold a separator, a quote or a newline", () => {
    expect(csvField("plain")).toBe("plain");
    expect(csvField("a,b")).toBe('"a,b"');
    expect(csvField('say "hi"')).toBe('"say ""hi"""');
    expect(csvField(null)).toBe("");
    expect(csvField(3)).toBe("3");
  });

  it("writes a header line and one line per row", () => {
    const csv = toCsv(
      [
        { name: "Acme, Inc", n: 2 },
        { name: "Globex", n: 0 },
      ],
      [
        { header: "Name", value: (row) => row.name },
        { header: "Count", value: (row) => row.n },
      ],
    );

    expect(csv).toBe('Name,Count\n"Acme, Inc",2\nGlobex,0\n');
  });

  it("reads saved views and drops damaged entries", () => {
    expect(parseViews("not json")).toStrictEqual([]);
    expect(parseViews('{"a":1}')).toStrictEqual([]);
    expect(
      parseViews('[{"name":"Open","search":"status=open"}]'),
    ).toStrictEqual([{ name: "Open", search: "status=open" }]);
    expect(parseViews('[{"name":1}]')).toStrictEqual([]);
  });
});
