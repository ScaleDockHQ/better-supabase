import { execFile } from "node:child_process";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { VERSION } from "../src/version.ts";

const bin = join(import.meta.dirname, "../bin/better-supabase.js");

interface Spawned {
  readonly code: number;
  readonly stdout: string;
  readonly stderr: string;
}

/** Runs the built bin the way a shell does; Turbo builds before `test`. */
function spawn(args: readonly string[], cwd: string): Promise<Spawned> {
  return new Promise((resolve) => {
    const child = execFile(
      process.execPath,
      [bin, ...args],
      { cwd, env: { NO_COLOR: "1" } },
      (error, stdout, stderr) => {
        resolve({ code: error ? Number(error.code) : 0, stdout, stderr });
      },
    );
    child.stdin?.end();
  });
}

describe("the built bin", () => {
  let dir: string;
  beforeAll(async () => {
    dir = await mkdtemp(join(tmpdir(), "better-supabase-bin-"));
  });
  afterAll(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  it("prints the version and the usage", async () => {
    expect(await spawn(["--version"], dir)).toEqual({
      code: 0,
      stdout: `${VERSION}\n`,
      stderr: "",
    });
    const usage = await spawn(["--help"], dir);
    expect(usage.code).toBe(0);
    expect(usage.stdout).toContain("USAGE better-supabase");
  });

  it("exits 2 with Problem Details for a mistyped command under --json", async () => {
    const result = await spawn(["genn", "--json"], dir);
    expect(result.code).toBe(2);
    expect(JSON.parse(result.stdout)).toMatchObject({
      code: "unknown_command",
      suggestion: "gen",
    });
  });

  it("reads the connection string from stdin", async () => {
    const result = await spawn(["seed", "--db-url-stdin", "--json"], dir);
    expect(result.code).toBe(2);
    expect(JSON.parse(result.stdout)).toMatchObject({
      code: "missing_value",
      flag: "--db-url-stdin",
    });
  });
});
