import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../src/sql/index.ts";

const dataOf = (names: string[]) =>
  renderBlocks(names, {})
    .filter((file) => file.kind === "data" && file.module === "tasks")
    .map((file) => file.contents)
    .join("\n");

describe("subject.realtime on block entities", () => {
  it("tracks the entity table when realtime-tables is installed", () => {
    expect(dataOf(["realtime-tables", "tasks"])).toContain(
      "select better_supabase.track_realtime('better_supabase.tasks', tenant_column => 'tenant_id'",
    );
  });

  it("leaves the table alone without realtime-tables", () => {
    expect(dataOf(["tasks"])).not.toContain("track_realtime");
  });
});
