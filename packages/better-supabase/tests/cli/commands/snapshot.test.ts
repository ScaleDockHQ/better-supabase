import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import {
  loadSnapshot,
  managementTarget,
  openSource,
  parseSnapshot,
  serializeSnapshot,
  snapshotFile,
} from "../../../src/cli/commands/snapshot.ts";
import {
  type BetterSupabaseConfig,
  resolveConfig,
} from "../../../src/config/index.ts";
import { fakeConnect } from "../fixtures/fake-connect.ts";
import { fakeSql } from "../fixtures/fake-sql.ts";
import { snapshotFixture as fixture } from "../fixtures/library.ts";

const config = (source: BetterSupabaseConfig["source"] = {}, root = "/p") =>
  resolveConfig({ source }, root);

describe("managementTarget", () => {
  it("reads a project ref from the flag or the config", () => {
    const env = { SUPABASE_ACCESS_TOKEN: "sbp_env" };
    expect(managementTarget(config(), env, { projectRef: "abc" })).toEqual({
      projectRef: "abc",
      accessToken: "sbp_env",
    });
    expect(
      managementTarget(
        config({ projectRef: "cfg", accessToken: "sbp_cfg" }),
        { ...env, SUPABASE_API_URL: "http://api.test" },
        {},
      ),
    ).toEqual({
      projectRef: "cfg",
      accessToken: "sbp_cfg",
      apiUrl: "http://api.test",
    });
  });

  it("prefers database URLs over a project ref", () => {
    const env = { SUPABASE_ACCESS_TOKEN: "t" };
    expect(
      managementTarget(config(), env, {
        dbUrl: "postgres://x",
        projectRef: "a",
      }),
    ).toBeUndefined();
    expect(
      managementTarget(
        config({ dbUrl: "postgres://x", projectRef: "cfg" }),
        env,
        {},
      ),
    ).toBeUndefined();
    expect(managementTarget(config(), env, {})).toBeUndefined();
  });

  it("asks for an access token", () => {
    expect(() => managementTarget(config(), {}, { projectRef: "abc" })).toThrow(
      "Reading project abc needs a Supabase access token. Set SUPABASE_ACCESS_TOKEN",
    );
  });
});

describe("openSource", () => {
  it("opens a piped URL, the Management API, then DATABASE_URL", async () => {
    const open = fakeConnect(fakeSql().pg);
    const direct = await openSource(
      config(),
      {},
      { dbUrl: "postgresql://u:pw@h/db" },
      open.connect,
    );
    expect(direct.describe).toBe("postgresql://u:***@h/db");

    const hosted = await openSource(
      config(),
      { SUPABASE_ACCESS_TOKEN: "t" },
      { projectRef: "abc" },
      open.connect,
    );
    expect(hosted.describe).toBe("project abc (Management API)");

    await openSource(
      config(),
      { DATABASE_URL: "postgresql://env/db" },
      {},
      open.connect,
    );
    expect(open.urls).toEqual([
      "postgresql://u:pw@h/db",
      "postgresql://env/db",
    ]);
  });
});

describe("snapshotFile", () => {
  it("uses the flag, then source.snapshot unless a database is asked for", () => {
    const saved = config({ snapshot: "supabase/snapshot.json" });
    expect(snapshotFile(saved, { snapshotPath: "s.json" })).toBe("s.json");
    expect(snapshotFile(saved, {})).toBe("supabase/snapshot.json");
    expect(snapshotFile(saved, { live: true })).toBeUndefined();
    expect(snapshotFile(saved, { dbUrl: "x" })).toBeUndefined();
    expect(snapshotFile(saved, { projectRef: "x" })).toBeUndefined();
    expect(snapshotFile(config(), {})).toBeUndefined();
  });
});

describe("loadSnapshot", () => {
  let root: string;

  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "better-supabase-snapshot-"));
  });

  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
  });

  async function write(path: string, contents: string): Promise<void> {
    await mkdir(dirname(join(root, path)), { recursive: true });
    await writeFile(join(root, path), contents);
  }

  it("reads a saved file and reports a missing one", async () => {
    await write("snap.json", JSON.stringify(fixture));
    const loaded = await loadSnapshot(
      config({}, root),
      {},
      {
        snapshotPath: "snap.json",
      },
    );
    expect(loaded.extras.tables).toHaveLength(fixture.extras.tables.length);
    await expect(
      loadSnapshot(config({}, root), {}, { snapshotPath: "gone.json" }),
    ).rejects.toThrow("Snapshot not found: gone.json");
  });

  it("introspects the configured schemas plus better_supabase, with the config.toml hooks", async () => {
    await write(
      "supabase/config.toml",
      '[auth.hook.custom_access_token]\nenabled = true\nuri = "pg-functions://postgres/rbac/hook"\n',
    );
    const db = fakeSql();
    const open = fakeConnect(db.pg);
    const snapshot = await loadSnapshot(
      resolveConfig({ schemas: ["public", "api"] }, root),
      {},
      { dbUrl: "postgresql://local/db" },
      open.connect,
    );
    expect(snapshot.schemas).toEqual(["api", "better_supabase", "public"]);
    expect(snapshot.extras.hooks).toEqual([
      {
        hook: "custom_access_token",
        schema: "rbac",
        name: "hook",
        functions: [],
      },
    ]);
    expect(
      db.texts().find((text) => text.includes("c.reltuples >=")),
    ).toContain("array['api', 'better_supabase', 'public']::text[]");
    expect(open.closed()).toBe(1);
  });

  it("closes the connection when introspection fails", async () => {
    const db = fakeSql([
      [/./, { throws: new Error("relation does not exist") }],
    ]);
    const open = fakeConnect(db.pg);
    await expect(
      loadSnapshot(
        config({}, root),
        {},
        { dbUrl: "postgresql://x/y" },
        open.connect,
      ),
    ).rejects.toThrow("relation does not exist");
    expect(open.closed()).toBe(1);
  });
});

describe("parseSnapshot", () => {
  it("rejects documents that are not v2 snapshots", async () => {
    await expect(parseSnapshot(null, "s.json")).rejects.toThrow(
      "s.json is not a version 2 snapshot.",
    );
    await expect(parseSnapshot({ version: 1 })).rejects.toThrow(
      "snapshot is not a version 2 snapshot.",
    );
    await expect(parseSnapshot({ version: 2, schemas: [] })).rejects.toThrow(
      'snapshot is missing "schemas" or "extras".',
    );
    await expect(
      parseSnapshot({ version: 2, schemas: "x", extras: { tables: [] } }),
    ).rejects.toThrow('is missing "schemas" or "extras"');
    await expect(
      parseSnapshot({ version: 2, schemas: [], extras: { tables: {} } }),
    ).rejects.toThrow('is missing "schemas" or "extras"');
    await expect(
      parseSnapshot(
        {
          version: 2,
          schemas: [],
          generator: { version: 9 },
          extras: { tables: [] },
        },
        "old.json",
      ),
    ).rejects.toThrow(/^old\.json has invalid "generator" metadata: /);
  });

  it("fills in what older snapshots lack and keeps what newer ones carry", async () => {
    const older = await parseSnapshot({
      version: 2,
      schemas: ["public"],
      generator: fixture.generator,
      extras: { tables: [] },
    });
    expect(older.extras).toEqual({ tables: [], buckets: [], realtime: [] });
    const full = await parseSnapshot(fixture);
    expect(Object.keys(full.extras).sort()).toEqual(
      [
        "buckets",
        "functions",
        "hooks",
        "realtime",
        "roleSettings",
        "tables",
      ].filter((key) => key in fixture.extras),
    );
  });
});

describe("serializeSnapshot", () => {
  it("writes the published $schema first and ends with a newline", async () => {
    const text = serializeSnapshot({
      ...(await parseSnapshot(fixture)),
      $schema: "./local.json",
    });
    expect(
      text.startsWith(
        '{\n  "$schema": "https://unpkg.com/better-supabase/schemas/snapshot-v2.json",\n  "version": 2,',
      ),
    ).toBe(true);
    expect(text.endsWith("}\n")).toBe(true);
  });
});
