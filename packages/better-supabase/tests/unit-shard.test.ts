import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import * as v from "valibot";
import { describe, expect, it } from "vitest";

import { assignShard, readDurations } from "./unit-shard.ts";

describe("assignShard", () => {
  const durations = new Map([
    ["a", 100],
    ["b", 80],
    ["c", 60],
    ["d", 40],
  ]);

  it("puts the longest file on the lightest shard", () => {
    const files = ["a", "b", "c", "d"];

    const shard = (index: number) =>
      assignShard(files, (file) => file, durations, index, 2);

    expect(shard(1)).toEqual(["a", "d"]);
    expect(shard(2)).toEqual(["b", "c"]);
  });

  it("weighs an unmeasured file as the median", () => {
    // Median of 40, 60, 80 and 100 is 60, under b's 80, so e joins b.
    expect(
      assignShard(["a", "b", "e"], (file) => file, durations, 2, 2),
    ).toEqual(["b", "e"]);
  });

  it("returns every file when there is one shard", () => {
    expect(assignShard(["b", "a"], (file) => file, durations, 1, 1)).toEqual([
      "b",
      "a",
    ]);
  });

  it("returns nothing for a shard index outside the count", () => {
    expect(assignShard(["a"], (file) => file, durations, 3, 2)).toEqual([]);
  });
});

describe("readDurations", () => {
  it("reads a path-to-milliseconds object", () => {
    const dir = mkdtempSync(join(tmpdir(), "unit-shard-"));
    const path = join(dir, "durations.json");

    writeFileSync(path, '{"tests/a.test.ts": 12}\n');

    expect(readDurations(path)).toEqual(new Map([["tests/a.test.ts", 12]]));
  });

  it("rejects a duration that is not a number", () => {
    const dir = mkdtempSync(join(tmpdir(), "unit-shard-"));
    const path = join(dir, "durations.json");

    writeFileSync(path, '{"tests/a.test.ts": "slow"}\n');

    expect(() => readDurations(path)).toThrow(v.ValiError);
  });
});
