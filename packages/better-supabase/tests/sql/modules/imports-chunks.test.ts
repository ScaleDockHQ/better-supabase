import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

// The chunk lifecycle (ADR 1223): maintenance clears the items of ended runs
// after keepFailedItems and cancels a stale run only when staleAfter is set.
const imports = (options: Readonly<Record<string, unknown>> = {}): string =>
  renderBlocks(["audit", "imports"], { modules: { imports: { options } } })
    .filter((file) => file.module === "imports")
    .map((file) => file.contents)
    .join("\n");

describe("import chunk maintenance", () => {
  it("keeps a failed chunk's items for 7 days and leaves runs alone by default", () => {
    const sql = imports();

    expect(sql).toContain(
      'create or replace function "better_supabase"."import_chunk_maintenance"()',
    );
    expect(sql).toContain("interval '7 days'");
    expect(sql).not.toContain("'stale'");
  });

  it("cancels a run whose heartbeat is older than staleAfter", () => {
    const sql = imports({
      chunks: { keepFailedItems: "2 days", staleAfter: "30 minutes" },
    });

    expect(sql).toContain("interval '2 days'");
    expect(sql).toContain("interval '30 minutes'");
    expect(sql).toContain("'stale'");
  });

  it("refuses an interval it cannot render", () => {
    expect(() => imports({ chunks: { keepFailedItems: "1 week" } })).toThrow(
      /keepFailedItems/u,
    );
  });
});
