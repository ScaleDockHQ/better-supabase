import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { run } from "../../../src/cli/core/run.ts";

describe("gen --save-snapshot", () => {
  let dir: string;

  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), "better-supabase-snapshot-"));
  });

  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  it.each([
    [["--save-snapshot", "--watch"], "it takes no --watch"],
    [["--save-snapshot", "--only", "types"], "it takes no --only"],
    [["--out", "s.json"], "--out works with --save-snapshot"],
    [["--kind", "snapshot"], "--kind works with --save-snapshot"],
  ])("refuses gen %j", async (argv, message) => {
    const result = await run(["gen", ...argv, "--cwd", dir]);

    expect(result.code).toBe(2);
    expect(result.stderr).toContain(message);
  });
});
