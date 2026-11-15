import { describe, expect, it } from "vitest";

import { resetSteps } from "./supabase-reset.ts";

describe("resetSteps", () => {
  it("resets, then seeds the entity pages", () => {
    expect(resetSteps([])).toEqual([
      ["supabase", ["db", "reset"]],
      ["node", ["scripts/seed-entity-pages.ts"]],
    ]);
  });

  it("passes its arguments to the reset", () => {
    expect(resetSteps(["--linked"])[0]).toEqual([
      "supabase",
      ["db", "reset", "--linked"],
    ]);
  });

  it("skips the page seeds for a library reset", () => {
    expect(resetSteps(["--sql-paths", "./seed.sql"])).toEqual([
      ["supabase", ["db", "reset", "--sql-paths", "./seed.sql"]],
    ]);
  });
});
