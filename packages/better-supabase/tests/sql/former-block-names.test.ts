import { describe, expect, it } from "vitest";

import { moduleFileVersion } from "../../src/sql/markers.ts";
import { renderBlocks } from "../../src/sql/render.ts";

describe("blocks renamed since they were installed", () => {
  it("reads a time-tracking file as the time-entries block", () => {
    expect(
      moduleFileVersion("-- @bsb-block time-tracking@2 managed\nselect 1;"),
    ).toEqual({ module: "time-entries", version: 2 });
    expect(
      moduleFileVersion("-- @bsb-block bulk@1 managed\nselect 1;")?.module,
    ).toBe("bulk-actions");
  });

  it("renames the registry row before it records the block", () => {
    const sql = renderBlocks(["time-entries"])
      .map((file) => file.contents)
      .join("\n");

    const rename = sql.indexOf(
      "update better_supabase.blocks set name = 'time-entries'",
    );

    expect(rename).toBeGreaterThan(-1);
    expect(rename).toBeLessThan(sql.indexOf("values ('time-entries'"));
    expect(sql).toContain("where name = 'time-tracking'");
  });
});
