import { describe, expect, it } from "vitest";

import { deprecationWarnings } from "../../../src/cli/gen/deprecations.ts";

const config = (exempt: unknown) =>
  // SAFETY: only `blocks.audit.options.exempt` is read.
  ({ blocks: { audit: { options: { exempt } } } }) as never;

describe("deprecationWarnings", () => {
  it("names the bare exempt strings", () => {
    expect(deprecationWarnings(config(["public.*_archive"]))).toEqual([
      expect.stringContaining("public.*_archive"),
    ]);
  });

  it("is quiet for { table, reason } entries and for no entries", () => {
    expect(
      deprecationWarnings(config([{ table: "public.x", reason: "log" }])),
    ).toEqual([]);
    expect(deprecationWarnings({ blocks: {} })).toEqual([]);
  });
});
