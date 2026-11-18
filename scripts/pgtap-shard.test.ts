import { describe, expect, it } from "vitest";

import { pgtapFiles, pgtapShard } from "./pgtap-shard.ts";

describe("pgtapShard", () => {
  it("puts every pgTAP file in exactly one shard", () => {
    const files = pgtapFiles();

    const shards = [1, 2, 3].map((index) =>
      pgtapShard(files, new Map(), index, 3),
    );

    expect(files.length).toBeGreaterThan(0);
    expect(shards.flat().toSorted()).toEqual(files.toSorted());
  });

  it("places a file without a recorded duration", () => {
    const durations = new Map([
      ["a.sql", 9000],
      ["b.sql", 1000],
    ]);

    const files = ["a.sql", "b.sql", "new.sql"];

    expect(
      [
        ...pgtapShard(files, durations, 1, 2),
        ...pgtapShard(files, durations, 2, 2),
      ].toSorted(),
    ).toEqual(files);
  });
});
