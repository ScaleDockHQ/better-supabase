import { describe, expect, it } from "vitest";

import {
  diffItems,
  stableJson,
} from "../../../src/blocks/imports/diff-items.ts";
import { renderBlocks } from "../../../src/sql/render.ts";

describe("diffItems", () => {
  it("reports created, changed and a source time that is not newer", async () => {
    const same = { data: { name: "A" }, refs: null };
    const bytes = new TextEncoder().encode(stableJson(same));
    const digest = await crypto.subtle.digest("SHA-256", bytes);

    const hash = [...new Uint8Array(digest)]
      .map((byte) => byte.toString(16).padStart(2, "0"))
      .join("");

    const diff = await diffItems(
      [
        { key: "new", data: { name: "B" } },
        {
          key: "old",
          data: { name: "changed" },
          sourceUpdatedAt: "2020-01-01T00:00:00Z",
        },
        { key: "edit", data: { name: "C" } },
        { key: "kept", data: same.data },
      ],
      {
        old: { hash: "unused", sourceUpdatedAt: "2024-01-01T00:00:00Z" },
        edit: { hash },
        kept: { hash },
      },
    );

    expect(diff.created).toEqual(["new"]);
    expect(diff.unchanged).toEqual(["old", "kept"]);
    expect(diff.changed).toEqual(["edit"]);
  });
});

describe("source updated at", () => {
  it("skips a row before hashing when the source time is not newer", () => {
    const sql = renderBlocks(["imports"])
      .map((file) => file.contents)
      .join("\n");

    const skip = sql.indexOf("v_source_at <=");
    const hash = sql.indexOf("v_hash :=", skip);

    expect(sql).toContain("source_updated_at");
    expect(skip).toBeGreaterThan(0);
    expect(hash).toBeGreaterThan(skip);
  });
});
