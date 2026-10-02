import {
  type BetterSupabaseConfig,
  resolveConfig,
} from "better-supabase/config";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { parseCommandArgs } from "../../src/command.ts";
import {
  doctorCommand,
  type DoctorArgs,
  runDoctor,
} from "../../src/commands/doctor.ts";
import { parseSnapshot } from "../../src/commands/snapshot.ts";
import { fakeConnect } from "../fixtures/fake-connect.ts";
import { fakeFetch } from "../fixtures/fake-fetch.ts";
import { fakeSql } from "../fixtures/fake-sql.ts";
import { snapshotFixture as fixture } from "../fixtures/library.ts";

interface Report {
  findings: { code: string; severity: string; message: string }[];
}

const TEMP_FILES = [
  "pg_stat_database",
  [{ temp_files: 3, temp_bytes: 3 * 1024 * 1024, work_mem: "4MB" }],
] as const;

describe("doctor command", () => {
  let root: string;

  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "better-supabase-doctor-cmd-"));
  });

  afterEach(async () => {
    vi.unstubAllGlobals();
    await rm(root, { recursive: true, force: true });
  });

  async function write(path: string, contents: string): Promise<void> {
    await mkdir(dirname(join(root, path)), { recursive: true });
    await writeFile(join(root, path), contents);
  }

  const doctor = (
    argv: string[],
    options: Parameters<typeof runDoctor>[3] = {},
    config: BetterSupabaseConfig = {},
    env: Record<string, string> = {},
  ) =>
    runDoctor(
      resolveConfig(config, root),
      parseCommandArgs(doctorCommand, argv) as DoctorArgs,
      env,
      options,
    );

  const findings = (output: string | undefined): Report["findings"] =>
    (JSON.parse(output ?? "{}") as Report).findings;

  it("rejects conflicting or malformed claims before reading anything", async () => {
    const user = "8a6f1c3e-2b4d-4e5f-9a7b-1c2d3e4f5a6b";
    expect(await doctor(["--as", user, "--claims", "{}"])).toEqual({
      code: 2,
      error: "Pass --as or --claims, not both",
    });
    expect(await doctor(["--as", "alice"])).toEqual({
      code: 2,
      error: '--as takes a user id (uuid), got "alice"',
    });
    expect(await doctor(["--claims", "[1]"])).toEqual({
      code: 2,
      error: "--claims takes a JSON object",
    });
    expect((await doctor(["--claims", "{nope"])).error).toMatch(
      /^--claims is not valid JSON: /,
    );
  });

  it("reads the database once for the snapshot and once for live checks, then closes both", async () => {
    const db = fakeSql([TEMP_FILES]);
    const open = fakeConnect(db.pg);
    const result = await doctor(
      [
        "--db-url",
        "postgresql://u:pw@h/db",
        "--only",
        "BS208",
        "--format",
        "json",
      ],
      { connect: open.connect },
    );
    expect(result.code).toBe(0);
    expect(findings(result.output)).toEqual([
      expect.objectContaining({
        code: "BS208",
        severity: "warning",
        message: expect.stringContaining(
          "3 temporary files (3.0 MB) since the statistics were reset; work_mem is 4MB.",
        ),
      }),
    ]);
    expect(open.urls).toEqual([
      "postgresql://u:pw@h/db",
      "postgresql://u:pw@h/db",
    ]);
    expect(open.closed()).toBe(2);
  });

  it("runs splinter over the database and reports a download it cannot verify", async () => {
    const api = fakeFetch(() => ({ text: "select 'tampered';" }));
    vi.stubGlobal("fetch", api.fetch);
    const db = fakeSql();
    const open = fakeConnect(db.pg);
    const result = await doctor(
      ["--only", "BS100,BS200", "--format", "json"],
      { connect: open.connect },
      {},
      { DATABASE_URL: "postgresql://env/db" },
    );
    const reported = findings(result.output);
    expect(reported.map((finding) => finding.code)).toEqual(["BS100", "BS200"]);
    expect(reported[0]!.message).toMatch(
      /^The security advisor could not run \(database \(splinter\)\): /,
    );
    expect(api.calls).toHaveLength(1);
    expect(api.calls[0]!.url).toMatch(/\/splinter\.sql$/);
    expect(db.texts().some((text) => text.includes("tampered"))).toBe(false);
    expect(open.closed()).toBe(2);
  });

  it("reads a hosted project's advisors and statistics through the Management API", async () => {
    const api = fakeFetch((call) => {
      if (call.url.includes("/advisors/")) return { body: { lints: [] } };
      const query = JSON.parse(String(call.body)) as { query: string };
      return {
        body: query.query.includes("pg_stat_database") ? TEMP_FILES[1] : [],
      };
    });
    vi.stubGlobal("fetch", api.fetch);
    const open = fakeConnect(fakeSql().pg);
    const result = await doctor(
      ["--project-ref", "abc", "--only", "BS100,BS208", "--format", "json"],
      { connect: open.connect },
      {},
      { SUPABASE_ACCESS_TOKEN: "sbp_test" },
    );
    expect(findings(result.output).map((finding) => finding.code)).toEqual([
      "BS208",
    ]);
    expect(open.urls).toEqual([]);
    const urls = api.calls.map((call) => call.url);
    expect(urls).toContain(
      "https://api.supabase.com/v1/projects/abc/advisors/security",
    );
    expect(
      urls.every((url) =>
        url.startsWith("https://api.supabase.com/v1/projects/abc/"),
      ),
    ).toBe(true);
  });

  it("skips the advisors and live checks for a saved snapshot", async () => {
    await write("snapshot.json", JSON.stringify(fixture));
    const result = await doctor([
      "--snapshot",
      "snapshot.json",
      "--only",
      "BS100,BS208",
      "--format",
      "json",
    ]);
    expect(findings(result.output)).toEqual([
      expect.objectContaining({
        code: "BS100",
        severity: "info",
        message:
          "Skipped the security advisor: reading the saved snapshot snapshot.json; pass --db-url or --project-ref to check a database.",
      }),
    ]);
  });

  it("prints only the hook grant SQL with --fix-grants", async () => {
    expect(
      await doctor(["--fix-grants"], { snapshot: parseSnapshot(fixture) }),
    ).toEqual({
      code: 0,
      output: "-- Every configured Auth hook function has its grants.",
    });
  });

  it("scans doctor.sources, skipping node_modules", async () => {
    const snapshot = parseSnapshot({
      ...fixture,
      extras: { ...fixture.extras, roleSettings: {} },
    });
    await write("node_modules/dep/index.ts", "db.notes.aggregate({});\n");
    const clean = await doctor(["--only", "BS210", "--format", "json"], {
      snapshot,
    });
    expect(findings(clean.output)).toEqual([]);

    await write("src/z.ts", "\n\ndb.notes.aggregate({});\n");
    await write("src/a.ts", "db.notes.list({ facetCounts: true });\n");
    const result = await doctor(["--only", "BS210", "--format", "json"], {
      snapshot,
    });
    expect(findings(result.output)).toEqual([
      expect.objectContaining({
        code: "BS210",
        message: expect.stringMatching(/^src\/a\.ts uses aggregates/),
      }),
    ]);
  });

  it("skips the read-sets kit file when config.readSets cannot load", async () => {
    const snapshot = parseSnapshot(fixture);
    const config = { sql: { kit: ["read-sets"] } };
    const loaded = await doctor(
      ["--only", "BS304", "--format", "json"],
      { snapshot },
      config,
    );
    expect(findings(loaded.output).map((finding) => finding.code)).toEqual([
      "BS304",
    ]);
    const skipped = await doctor(
      ["--only", "BS304", "--format", "json"],
      { snapshot },
      { ...config, readSets: ["src/missing.ts"] },
    );
    expect(findings(skipped.output)).toEqual([]);
  });
});
