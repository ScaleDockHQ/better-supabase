import { chmod, mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type { BetterSupabaseConfig } from "../../../src/config/index.ts";

import {
  loadSnapshot,
  managementTarget,
  openSource,
  parseSnapshot,
  serializeSnapshot,
  snapshotFile,
} from "../../../src/cli/commands/snapshot.ts";
import { resolveConfig } from "../../../src/config/index.ts";
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

  it("asks for an access token with auth_required", () => {
    expect(() => managementTarget(config(), {}, { projectRef: "abc" })).toThrow(
      expect.objectContaining({
        code: "auth_required",
        exitCode: 3,
        message: expect.stringContaining(
          "Reading project abc needs a Supabase access token. Set SUPABASE_ACCESS_TOKEN",
        ),
      }),
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

  it("prefers DATABASE_URL to SUPABASE_DB_URL and reads either alone", async () => {
    const open = fakeConnect(fakeSql().pg);
    await openSource(
      config(),
      {
        DATABASE_URL: "postgresql://database-url/db",
        SUPABASE_DB_URL: "postgresql://supabase-db-url/db",
      },
      {},
      open.connect,
    );
    await openSource(
      config(),
      { SUPABASE_DB_URL: "postgresql://supabase-db-url/db" },
      {},
      open.connect,
    );
    expect(open.urls).toEqual([
      "postgresql://database-url/db",
      "postgresql://supabase-db-url/db",
    ]);
  });
});

describe("openSource on the local stack", () => {
  let root: string;

  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "bs-local-source-"));
    await writeFile(join(root, ".git"), "");
    await mkdir(join(root, "supabase"));
  });

  afterEach(() => rm(root, { recursive: true, force: true }));

  async function fakeSupabase(script: string): Promise<string> {
    const bin = join(root, "fake-supabase");
    await writeFile(bin, `#!/bin/sh\n${script}\n`);
    await chmod(bin, 0o755);

    return bin;
  }

  it("uses the [db] port from config.toml", async () => {
    await writeFile(join(root, "supabase/config.toml"), "[db]\nport = 55422\n");
    const open = fakeConnect(fakeSql().pg);
    await openSource(config({}, root), {}, {}, open.connect);
    expect(open.urls).toEqual([
      "postgresql://postgres:postgres@127.0.0.1:55422/postgres",
    ]);
  });

  it("asks the stack engine for DB_URL when config.toml sets no port", async () => {
    await writeFile(
      join(root, "supabase/config.toml"),
      "[experimental]\nstack = true\n",
    );

    const bin = await fakeSupabase(
      `if [ "$2" = "-o" ]; then exit 1; fi\necho '{"DB_URL":"postgresql://postgres:postgres@127.0.0.1:28910/postgres"}'`,
    );

    const open = fakeConnect(fakeSql().pg);
    await openSource(config({}, root), { SUPABASE_BIN: bin }, {}, open.connect);
    expect(open.urls).toEqual([
      "postgresql://postgres:postgres@127.0.0.1:28910/postgres",
    ]);
  });

  it("fails instead of guessing port 54322 when no stack answers", async () => {
    await writeFile(join(root, "supabase/config.toml"), "[api]\n");
    const bin = await fakeSupabase("exit 1");
    const open = fakeConnect(fakeSql().pg);

    await expect(
      openSource(config({}, root), { SUPABASE_BIN: bin }, {}, open.connect),
    ).rejects.toMatchObject({ code: "not_found" });

    expect(open.urls).toEqual([]);
  });
});

describe("openSource on a Supabase Lite project", () => {
  let root: string;

  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "bs-lite-source-"));
    await writeFile(join(root, ".git"), "");
    await mkdir(join(root, "supabase"));
    await writeFile(
      join(root, "supabase/config.toml"),
      '[db]\ndriver = "postgres"\nurl = "postgresql://lite/db"\n',
    );
  });

  afterEach(() => rm(root, { recursive: true, force: true }));

  it("reads [db] url before DATABASE_URL, unless source.lite is false", async () => {
    const open = fakeConnect(fakeSql().pg);
    const env = { DATABASE_URL: "postgresql://env/db" };
    await openSource(config({}, root), env, {}, open.connect);
    await openSource(config({ lite: false }, root), env, {}, open.connect);
    expect(open.urls).toEqual(["postgresql://lite/db", "postgresql://env/db"]);
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
      { snapshotPath: "snap.json" },
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

  it("closes the connection when config.toml can't be read", async () => {
    await mkdir(join(root, "supabase/config.toml"), { recursive: true });
    const db = fakeSql([]);
    const open = fakeConnect(db.pg);
    await expect(
      loadSnapshot(
        config({}, root),
        {},
        { dbUrl: "postgresql://x/y" },
        open.connect,
      ),
    ).rejects.toThrow("EISDIR");
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
    expect(Object.keys(full.extras).toSorted()).toEqual(
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
