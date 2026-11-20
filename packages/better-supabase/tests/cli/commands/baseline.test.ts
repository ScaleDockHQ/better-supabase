import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { applyBaseline } from "../../../src/cli/baseline/apply.ts";
import { buildBaseline } from "../../../src/cli/baseline/build.ts";
import { stackInfo } from "../../../src/cli/baseline/stack.ts";
import { verifyBaseline } from "../../../src/cli/baseline/verify.ts";
import { run } from "../../../src/cli/core/run.ts";

vi.mock(import("../../../src/cli/baseline/build.ts"), () => ({
  buildBaseline: vi.fn(),
}));

vi.mock(import("../../../src/cli/baseline/apply.ts"), () => ({
  applyBaseline: vi.fn(),
}));

vi.mock(import("../../../src/cli/baseline/verify.ts"), () => ({
  verifyBaseline: vi.fn(),
}));

vi.mock(
  import("../../../src/cli/baseline/stack.ts"),
  async (importOriginal) => ({
    ...(await importOriginal()),
    stackInfo: vi.fn(),
  }),
);

const KEY = "0123456789abcdef".repeat(4);
const env = { BSB_AGENT: "no" };

let dir: string;
const lines: string[] = [];
const io = { stdout: (): void => {}, stderr: (): void => {} };

beforeEach(async () => {
  dir = await mkdtemp(join(tmpdir(), "bsb-baseline-cmd-"));
  lines.length = 0;
});

afterEach(async () => {
  vi.clearAllMocks();
  await rm(dir, { recursive: true, force: true });
});

const local = {
  id: "local",
  dbUrl: "postgresql://postgres:postgres@127.0.0.1:54322/postgres",
  apiUrl: "http://127.0.0.1:54321",
  serviceKey: "secret",
};

describe("baseline build", () => {
  it("passes the flags and prints the key, the check and the timings", async () => {
    vi.mocked(buildBaseline).mockImplementation((ctx) => {
      ctx.log("Replaying 2 migrations");

      return Promise.resolve({
        key: KEY,
        dir: join(dir, KEY),
        cached: false,
        withSeed: true,
        timings: { replay: 1500 },
        tables: 2,
        seedTables: 1,
        objects: 0,
        verified: true,
      });
    });

    const result = await run(
      [
        "baseline",
        "build",
        "--with-seed",
        "--force",
        "--verify",
        "--out",
        "cache",
        "--cwd",
        dir,
      ],
      { env, io: { ...io, stderr: (line: string) => lines.push(line) } },
    );

    expect(result.code).toBe(0);
    expect(result.stdout).toContain(
      `Built baseline ${KEY.slice(0, 12)} in ${join(dir, KEY)}.`,
    );
    expect(result.stdout).toContain("Verified against a full replay.");
    expect(result.stdout).toContain("  replay: 1.5 s");
    expect(lines.join("")).toContain("Replaying 2 migrations");
    expect(vi.mocked(buildBaseline).mock.calls[0]?.[1]).toEqual({
      withSeed: true,
      out: "cache",
      force: true,
      verify: true,
    });
  });

  it("says when a baseline already covers the migrations", async () => {
    vi.mocked(buildBaseline).mockResolvedValue({
      key: KEY,
      dir,
      cached: true,
      withSeed: false,
      timings: {},
      tables: 0,
      seedTables: 0,
      objects: 0,
      verified: false,
    });

    const result = await run(["baseline", "build", "--cwd", dir], { env, io });

    expect(result.stdout).toContain(
      `Baseline ${KEY.slice(0, 12)} already covers these migrations.`,
    );
    expect(result.stdout).not.toContain("Verified");
    expect(vi.mocked(buildBaseline).mock.calls[0]?.[1]).toEqual({
      withSeed: false,
      out: undefined,
      force: false,
      verify: false,
    });
  });
});

describe("baseline apply", () => {
  it("fills the local stack and reports the newer migrations and seeds", async () => {
    vi.mocked(stackInfo).mockResolvedValue(local);
    vi.mocked(applyBaseline).mockImplementation(async (ctx, options) => {
      ctx.log("Loading");
      await options.target.migrate();

      return {
        mode: "baseline",
        key: KEY,
        pending: ["20240103000000_more.sql"],
        seed: "snapshot",
        timings: { "load baseline": 500, migrations: 1500 },
      };
    });

    const result = await run(
      ["baseline", "apply", "--with-seed", "--from", "cache", "--cwd", dir],
      { env: { ...env, SUPABASE_BIN: process.execPath }, io },
    );

    expect(result.code).toBe(0);
    expect(result.stdout).toContain(
      `Loaded baseline ${KEY.slice(0, 12)}, then ran 1 newer migration(s).`,
    );
    expect(result.stdout).toContain("Seeds: snapshot.");
    expect(result.stdout).toContain("  total: 2.0 s");

    const options = vi.mocked(applyBaseline).mock.calls[0]?.[1];

    expect(options).toMatchObject({
      from: "cache",
      withSeed: true,
      target: {
        dbUrl: local.dbUrl,
        storage: { apiUrl: local.apiUrl, serviceKey: "secret" },
      },
    });
  });

  it("reports a replay and leaves out the storage target without a key", async () => {
    vi.mocked(stackInfo).mockResolvedValue({ ...local, serviceKey: undefined });
    vi.mocked(applyBaseline).mockResolvedValue({
      mode: "replay",
      reason: "no baseline in cache",
      pending: [],
      seed: "none",
      timings: {},
    });

    const result = await run(["baseline", "apply", "--cwd", dir], { env, io });

    expect(result.stdout).toContain(
      "Ran every migration (no baseline in cache).",
    );
    expect(result.stdout).not.toContain("Seeds:");
    expect(
      vi.mocked(applyBaseline).mock.calls[0]?.[1].target.storage,
    ).toBeUndefined();
  });

  it("refuses a database that is not local", async () => {
    vi.mocked(stackInfo).mockResolvedValue({
      ...local,
      dbUrl: "postgresql://postgres@db.example.com:5432/postgres",
    });

    const result = await run(["baseline", "apply", "--cwd", dir], { env, io });

    expect(result.code).not.toBe(0);
    expect(result.stderr).toContain(
      "baseline apply only fills a local database.",
    );
    expect(applyBaseline).not.toHaveBeenCalled();
  });
});

describe("baseline verify", () => {
  it("passes the folder and prints the result", async () => {
    vi.mocked(verifyBaseline).mockImplementation((ctx) => {
      ctx.log("Restoring");

      return Promise.resolve({
        key: KEY,
        schemaActions: 0,
        fingerprintMatches: true,
        mismatchedCounts: [],
      });
    });

    const result = await run(
      ["baseline", "verify", "--with-seed", "--from", "cache", "--cwd", dir],
      { env, io },
    );

    expect(result.stdout).toContain(
      `Baseline ${KEY.slice(0, 12)} restores to the same catalog, digest and row counts as a full replay.`,
    );
    expect(vi.mocked(verifyBaseline).mock.calls[0]?.[1]).toEqual({
      out: "cache",
      withSeed: true,
    });
  });
});
