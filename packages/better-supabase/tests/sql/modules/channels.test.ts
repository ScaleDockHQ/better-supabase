import { describe, expect, it } from "vitest";

import { moduleBody } from "../../../src/sql/render.ts";

describe("channels module", () => {
  it("builds the table and its functions on the messaging core", () => {
    const sql = moduleBody("channels", { modules: {} })!;

    expect(sql).toContain("create table if not exists");
    expect(sql).toContain("open_conversation");
    expect(sql).toContain("channels_for_record");
  });

  it("renders nothing for a custom implementation", () => {
    expect(
      moduleBody("channels", { modules: { channels: { mode: "custom" } } }),
    ).toBeFalsy();
  });
});
