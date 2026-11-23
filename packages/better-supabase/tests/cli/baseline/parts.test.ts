import { access, chmod, mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type {
  BaselineManifest,
  BaselineVersions,
} from "../../../src/cli/baseline/key.ts";
import type { BaselineContext } from "../../../src/cli/baseline/stack.ts";
import type { ExecResult } from "../../../src/cli/exec.ts";

import {
  artifactFiles,
  findArtifact,
  readManifest,
} from "../../../src/cli/baseline/artifact.ts";
import { pgmqQueues } from "../../../src/cli/baseline/catalog.ts";
import {
  BASELINE_FORMAT,
  matchBaseline,
  schemaKey,
} from "../../../src/cli/baseline/key.ts";
import { missingTool, pgTool } from "../../../src/cli/baseline/pg-tools.ts";
import {
  packBuckets,
  seedSources,
  unpackBuckets,
  uploadBuckets,
} from "../../../src/cli/baseline/seeds.ts";
import {
  baselineContext,
  cliVersion,
  runPg,
  stackInfo,
  stepTimer,
} from "../../../src/cli/baseline/stack.ts";
import { parseEnv } from "../../../src/cli/env.ts";
import { makeSupabaseConfig } from "../../../src/cli/supabase-config.ts";

const env = parseEnv({});

const versions: BaselineVersions = {
  bsb: "1.0.0",
  supabaseCli: "2.40.0",
  postgres: "17.6",
  engine: "1",
};

const migration = {
  file: "supabase/migrations/20240101000000_a.sql",
  sha256: "a",
};

let dir: string;

beforeEach(async () => {
  dir = await mkdtemp(join(tmpdir(), "bsb-baseline-parts-"));
});

afterEach(async () => {
  await rm(dir, { recursive: true, force: true });
});

function context(
  supabase: (args: readonly string[]) => ExecResult,
  run: (command: string, args: readonly string[]) => ExecResult = () => ({
    code: 0,
    stdout: "",
    stderr: "",
  }),
): BaselineContext {
  return {
    root: dir,
    env,
    log: () => {},
    supabase: (args) => Promise.resolve(supabase(args)),
    run: (command, args) => Promise.resolve(run(command, args)),
  };
}

describe("findArtifact", () => {
  async function write(key: string, manifest: unknown): Promise<void> {
    const files = artifactFiles(dir, key);
    await mkdir(files.dir, { recursive: true });
    await writeFile(
      files.manifest,
      typeof manifest === "string" ? manifest : JSON.stringify(manifest),
    );
  }

  const manifest = (
    overrides: Partial<BaselineManifest> = {},
  ): BaselineManifest => ({
    format: BASELINE_FORMAT,
    key: schemaKey([migration], versions),
    createdAt: "2026-11-20T00:00:00.000Z",
    versions,
    migrations: [migration],
    counts: {},
    fingerprint: {},
    ...overrides,
  });

  it("says no baseline exists in a missing folder", async () => {
    await expect(
      findArtifact(join(dir, "missing"), [migration], versions),
    ).resolves.toEqual({
      found: undefined,
      reason: `no baseline in ${join(dir, "missing")}`,
    });
  });

  it("skips unreadable manifests and explains the closest mismatch", async () => {
    await write("a-broken", "{");
    await mkdir(join(dir, "b-empty"));
    await write(
      "c-old",
      manifest({ versions: { ...versions, postgres: "16.4" } }),
    );

    await expect(
      readManifest(artifactFiles(dir, "a-broken").manifest),
    ).resolves.toBeUndefined();
    await expect(findArtifact(dir, [migration], versions)).resolves.toEqual({
      found: undefined,
      reason: "postgres is 17.6 here and 16.4 in the baseline",
    });
  });

  it("picks the artifact with the fewest migrations left to run", async () => {
    const later = {
      file: "supabase/migrations/20240102000000_b.sql",
      sha256: "b",
    };

    await write("older", manifest());
    await write("newer", manifest({ migrations: [migration, later] }));

    const search = await findArtifact(dir, [migration, later], versions);

    expect(search.found?.files.dir).toBe(join(dir, "newer"));
    expect(search.found?.match).toEqual({ ok: true, pending: [] });
  });
});

describe("matchBaseline", () => {
  it("rejects a new migration without a version", () => {
    const held = {
      format: BASELINE_FORMAT,
      key: "k",
      createdAt: "",
      versions,
      migrations: [migration],
      counts: {},
      fingerprint: {},
    };

    expect(
      matchBaseline(
        held,
        [migration, { file: "supabase/migrations/extra.sql", sha256: "x" }],
        versions,
      ),
    ).toEqual({ ok: false, reason: "migration extra.sql has no version" });
  });
});

describe("pgTool", () => {
  it("prefers $BETTER_SUPABASE_PG_BIN", async () => {
    await writeFile(join(dir, "psql"), "");

    expect(
      pgTool(
        "psql",
        parseEnv({ BETTER_SUPABASE_PG_BIN: dir }),
        join(dir, "home"),
      ),
    ).toBe(join(dir, "psql"));
    expect(
      pgTool(
        "pg_dump",
        parseEnv({ BETTER_SUPABASE_PG_BIN: dir }),
        join(dir, "home"),
      ),
    ).toBe("pg_dump");
  });

  it("finds the newest cached Postgres tools for this platform", async () => {
    const cache = join(dir, ".supabase/cache/stack/slim-services/postgres");
    const platform = `${process.platform}-${process.arch}`;

    for (const version of ["17.6.1", "17.10.0", "15.8.1"]) {
      await mkdir(join(cache, version, platform, "bin"), { recursive: true });
      await writeFile(join(cache, version, platform, "bin", "psql"), "");
    }

    await mkdir(join(cache, "18.0.0"));

    expect(pgTool("psql", env, dir)).toBe(
      join(cache, "17.10.0", platform, "bin", "psql"),
    );
  });

  it("falls back to the PATH without a cache", () => {
    expect(pgTool("psql", env, dir)).toBe("psql");
  });

  it("explains how to get a missing tool", () => {
    expect(missingTool("pg_dump", "not found").message).toContain(
      "baseline needs pg_dump, and it could not run: not found.",
    );
  });
});

describe("seedSources", () => {
  it("defaults to seed.sql and resolves absolute bucket folders", async () => {
    await mkdir(join(dir, "supabase"));
    await writeFile(join(dir, "supabase/seed.sql"), "select 1;\n");

    const sources = await seedSources(
      dir,
      makeSupabaseConfig({
        path: "supabase/config.toml",
        dir: "supabase",
        format: "toml",
        text: "",
        parser: "smol-toml",
        document: {
          storage: {
            buckets: {
              absolute: { objects_path: join(dir, "missing") },
              blank: { objects_path: "" },
              odd: "value",
            },
          },
        },
      }),
    );

    expect(sources).toEqual({
      sql: ["supabase/seed.sql"],
      buckets: [{ name: "absolute", folder: join(dir, "missing") }],
      files: ["supabase/seed.sql"],
    });
  });

  it("finds nothing without a config", async () => {
    await expect(seedSources(dir, undefined)).resolves.toEqual({
      sql: [],
      buckets: [],
      files: [],
    });
  });
});

describe("buckets", () => {
  const failing = context(
    () => ({ code: 0, stdout: "", stderr: "" }),
    () => ({ code: 2, stdout: "", stderr: "tar: cannot open\n" }),
  );

  it("reports a failed pack and cleans up", async () => {
    await expect(
      packBuckets(
        failing,
        [{ name: "avatars", folder: dir }],
        join(dir, "out.tar.gz"),
      ),
    ).rejects.toThrow("tar failed: tar: cannot open");
  });

  it("reports a failed unpack and removes its folder", async () => {
    let folder = "";

    const tar = context(
      () => ({ code: 0, stdout: "", stderr: "" }),
      (_command, args) => {
        folder = args.at(-1) ?? "";

        return { code: 2, stdout: "", stderr: "tar: cannot open\n" };
      },
    );

    await expect(
      unpackBuckets(tar, join(dir, "missing.tar.gz")),
    ).rejects.toThrow("tar failed: tar: cannot open");
    expect(folder).toContain("bsb-objects-");
    await expect(access(folder)).rejects.toThrow("ENOENT");
  });

  it("uploads nothing from an empty folder", async () => {
    await expect(
      uploadBuckets(
        [{ name: "empty", folder: dir }],
        { apiUrl: "http://x", serviceKey: "k" },
        () => Promise.reject(new Error("no upload expected")),
      ),
    ).resolves.toBe(0);
  });

  it("sends unknown file types as octet streams", async () => {
    await writeFile(join(dir, "blob.bin"), "x");
    const types: (string | null)[] = [];

    await uploadBuckets(
      [{ name: "b", folder: dir }],
      { apiUrl: "http://x", serviceKey: "k" },
      (_url, init) => {
        types.push(new Headers(init?.headers).get("content-type"));

        return Promise.resolve(new Response("{}"));
      },
    );

    expect(types).toEqual(["application/octet-stream"]);
  });
});

describe("stack", () => {
  const status = (body: unknown, code = 0): ExecResult => ({
    code,
    stdout: JSON.stringify(body),
    stderr: code === 0 ? "" : "no stack",
  });

  it("reads a named stack and falls back to the service role key", async () => {
    const calls: string[][] = [];

    const ctx = context((args) => {
      calls.push([...args]);

      return status({
        env: {
          DB_URL: "postgresql://a",
          API_URL: "",
          SERVICE_ROLE_KEY: "role",
        },
        identity: { id: "id-1" },
      });
    });

    await expect(stackInfo(ctx, "tests")).resolves.toEqual({
      id: "id-1",
      dbUrl: "postgresql://a",
      apiUrl: undefined,
      serviceKey: "role",
    });
    expect(calls).toEqual([
      ["status", "--stack", "tests", "--output-format", "json"],
    ]);
  });

  it.each([
    [
      "a failed status",
      status({}, 1),
      undefined,
      "supabase status found no running stack: no stack",
    ],
    [
      "no env or identity",
      status({ env: null, identity: "x" }),
      "tests",
      "no running stack named tests: {",
    ],
    [
      "no database URL",
      status({ env: { DB_URL: 1 }, identity: { id: "x" } }),
      undefined,
      "no running stack",
    ],
  ])("throws for %s", async (_name, result, name, message) => {
    await expect(
      stackInfo(
        context(() => result),
        name,
      ),
    ).rejects.toThrow(message);
  });

  it("reports a missing or failing Postgres tool", async () => {
    const missing = context(
      () => status({}),
      () => ({ code: 127, stdout: "", stderr: "psql: not found" }),
    );

    await expect(runPg(missing, "psql", [])).rejects.toThrow(
      "baseline needs psql",
    );

    const failing = context(
      () => status({}),
      () => ({ code: 1, stdout: "a\nb\nc\nd\n", stderr: "" }),
    );

    await expect(runPg(failing, "pg_dump", [])).rejects.toThrow(
      "pg_dump failed: b c d",
    );
  });

  it("times a step that throws", async () => {
    const timer = stepTimer();

    await expect(
      timer.step("fails", () => Promise.reject(new Error("boom"))),
    ).rejects.toThrow("boom");
    await timer.step("fails", () => Promise.resolve());
    expect(Object.keys(timer.timings)).toEqual(["fails"]);
  });

  it("reads the CLI version from its last line", async () => {
    await expect(
      cliVersion(context(() => ({ code: 0, stdout: "", stderr: "" }))),
    ).resolves.toBe("");
    await expect(
      cliVersion(
        context(() => ({ code: 0, stdout: "notice\n 2.40.0 \n", stderr: "" })),
      ),
    ).resolves.toBe("2.40.0");
  });

  it("runs the real Supabase CLI and processes by default", async () => {
    const bin = join(dir, "supabase");
    await writeFile(bin, '#!/bin/sh\necho "cli $*"\n');
    await chmod(bin, 0o755);

    const ctx = baselineContext(dir, parseEnv({ SUPABASE_BIN: bin }));

    await expect(
      ctx.supabase(["--version"], dir, ctx.env),
    ).resolves.toMatchObject({ code: 0, stdout: "cli --version\n" });
    await expect(ctx.run(bin, ["x"], dir, ctx.env)).resolves.toMatchObject({
      stdout: "cli x\n",
    });
    expect(() => {
      ctx.log("ignored");
    }).not.toThrow();
  });
});

describe("pgmqQueues", () => {
  it("returns no queues without the pgmq extension", async () => {
    await expect(
      pgmqQueues({
        query: <R>() =>
          // SAFETY: the to_regclass query selects one nullable text column.
          Promise.resolve({ rows: [{ found: null }] as R[] }),
      }),
    ).resolves.toEqual([]);
  });
});
