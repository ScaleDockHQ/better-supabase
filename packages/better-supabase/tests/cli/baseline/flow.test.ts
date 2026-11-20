import { mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import type { FakeWorld } from "../fixtures/fake-baseline.ts";

import { applyBaseline } from "../../../src/cli/baseline/apply.ts";
import {
  artifactFiles,
  baselineRoot,
} from "../../../src/cli/baseline/artifact.ts";
import { buildBaseline } from "../../../src/cli/baseline/build.ts";
import { verifyBaseline } from "../../../src/cli/baseline/verify.ts";
import { connect } from "../../../src/cli/db.ts";
import { loadPgDelta, openPgPool } from "../../../src/cli/in-stack-diff.ts";
import { MIGRATED, fakeProject, fakeWorld } from "../fixtures/fake-baseline.ts";
import { fakeFetch } from "../fixtures/fake-fetch.ts";

vi.mock(import("../../../src/cli/db.ts"), async (importOriginal) => ({
  ...(await importOriginal()),
  connect: vi.fn(),
}));

vi.mock(
  import("../../../src/cli/in-stack-diff.ts"),
  async (importOriginal) => ({
    ...(await importOriginal()),
    loadPgDelta: vi.fn(),
    openPgPool: vi.fn(),
  }),
);

let world: FakeWorld;
let uploads: ReturnType<typeof fakeFetch>;

beforeEach(async () => {
  world = fakeWorld(await fakeProject());
  vi.mocked(connect).mockImplementation(world.connect);
  vi.mocked(openPgPool).mockImplementation(world.openPool);
  vi.mocked(loadPgDelta).mockResolvedValue(world.delta);
  uploads = fakeFetch(() => ({ status: 200, body: {} }));
  vi.stubGlobal("fetch", uploads.fetch);
});

afterEach(async () => {
  vi.unstubAllGlobals();
  await rm(world.root, { recursive: true, force: true });
});

const build = (
  withSeed: boolean,
  extra: { force?: boolean; verify?: boolean } = {},
) =>
  buildBaseline(world.ctx, {
    withSeed,
    force: extra.force ?? false,
    verify: extra.verify ?? false,
  });

const apply = (
  withSeed: boolean,
  migrate = () => Promise.resolve({ code: 0, stdout: "", stderr: "" }),
) =>
  applyBaseline(world.ctx, {
    withSeed,
    target: {
      dbUrl: world.localUrl,
      storage: { apiUrl: "http://127.0.0.1:54321", serviceKey: "secret" },
      migrate: async () => {
        world.dbs.set("54322", MIGRATED);

        return migrate();
      },
    },
  });

describe("baseline build", () => {
  it("writes the schema plan, the rows, the seed snapshot and the bucket tarball", async () => {
    const result = await build(true);
    const files = artifactFiles(baselineRoot(world.root), result.key);

    expect(result).toMatchObject({
      cached: false,
      withSeed: true,
      tables: 2,
      seedTables: 2,
      objects: 2,
      verified: false,
    });
    expect(result.dir).toBe(files.dir);
    expect(Object.keys(result.timings)).toEqual(
      expect.arrayContaining(["empty stack", "replay", "dump data", "seeds"]),
    );

    const schema = await readFile(files.schema, "utf-8");

    expect(schema).toContain("set local role postgres;");
    expect(schema).toContain("create table migrated ();");
    expect(schema).toContain("create index on plans (id);");
    expect(schema).not.toContain("extensions.lookup");
    expect(schema).toContain("select pgmq.create('jobs');");
    expect(schema).toContain("select pgmq.create_unlogged('fast');");
    expect(schema).toContain("create trigger notify");

    const data = await readFile(files.data, "utf-8");

    expect(data).toContain("set session_replication_role = replica;");
    expect(data).toContain('-- rows of "public"."plans"');
    expect(data).toContain('copy "pgmq"."q_jobs" from stdin;\n1\t{}\n\\.');
    expect(data).toContain(
      `select pg_catalog.setval('"public"."plans_id_seq"', 2, true);`,
    );
    expect(data).not.toContain("delete from");

    const seedSchema = await readFile(files.seedSchema, "utf-8");

    expect(seedSchema).toContain("select pgmq.create('mail');");
    expect(seedSchema).toContain("create trigger audit");
    expect(seedSchema).not.toContain("create trigger notify");

    const seedData = await readFile(files.seedData, "utf-8");

    expect(seedData).toContain('delete from "public"."plans";');
    expect(seedData).toContain('"auth"."users"');

    const manifest = JSON.parse(await readFile(files.manifest, "utf-8"));

    expect(manifest.counts).toEqual({ "public.plans": 2, "pgmq.q_jobs": 1 });
    expect(manifest.seed.counts).toEqual({
      "auth.users": 1,
      "public.plans": 3,
    });
    expect(
      manifest.seed.files.map((file: { file: string }) => file.file),
    ).toEqual([
      "supabase/buckets/avatars/me.png",
      "supabase/buckets/avatars/nested/read me.txt",
      "supabase/seed.sql",
      "supabase/seeds/a.sql",
      "supabase/seeds/b.sql",
    ]);
    expect(manifest.versions).toEqual({
      bsb: expect.any(String),
      supabaseCli: "2.40.0",
      postgres: "17.6",
      engine: "engine-1",
    });

    await expect(readFile(files.seedStorage)).resolves.toBeInstanceOf(Buffer);
    expect(world.calls).toContain(
      "supabase stack destroy --stack-id id-bsb-baseline-empty --yes",
    );
    expect(world.calls).toContain(
      "supabase stack destroy --stack-id id-bsb-baseline-build --yes",
    );
  });

  it("reuses an artifact that covers the migrations unless forced", async () => {
    const first = await build(false);
    await mkdir(join(baselineRoot(world.root), "unrelated"));
    const again = await build(false);

    expect(again).toMatchObject({
      key: first.key,
      cached: true,
      withSeed: false,
      objects: 0,
    });
    expect(world.log).toContain(
      `Baseline ${first.key.slice(0, 12)} is already built`,
    );

    const withSeed = await build(true);

    expect(withSeed.cached).toBe(false);
    expect((await build(true)).cached).toBe(true);
    expect((await build(true, { force: true })).cached).toBe(false);
  });

  it("verifies the new artifact against the replay when asked", async () => {
    const result = await build(true, { verify: true });

    expect(result.verified).toBe(true);
    expect(world.calls).toContain(
      "supabase stack destroy --stack-id id-bsb-baseline-verify --yes",
    );
    expect(
      uploads.calls
        .map((call) => call.url)
        .toSorted((a, b) => a.localeCompare(b)),
    ).toEqual([
      "http://127.0.0.1:55002/storage/v1/object/avatars/me.png",
      "http://127.0.0.1:55002/storage/v1/object/avatars/nested/read%20me.txt",
    ]);
  });

  it("reports a stack that does not start", async () => {
    world.failStart = "port in use";

    await expect(build(false)).rejects.toThrow(
      "supabase start --stack bsb-baseline-empty failed: port in use",
    );
  });

  it("destroys the build stack when the replay cannot be read", async () => {
    world.seeded = {
      ...MIGRATED,
      queues: [{ queue_name: "big", is_partitioned: true, is_unlogged: false }],
    };

    await expect(build(true)).rejects.toThrow(
      "The pgmq queue big is partitioned",
    );
    expect(world.calls).toContain(
      "supabase stack destroy --stack-id id-bsb-baseline-build --yes",
    );
  });
});

describe("baseline apply", () => {
  it("runs every migration and the seed files when there is no baseline", async () => {
    const migrate = vi.fn(() =>
      Promise.resolve({ code: 0, stdout: "", stderr: "" }),
    );

    const result = await apply(true, migrate);

    expect(result).toMatchObject({ mode: "replay", seed: "files" });
    expect(result.reason).toContain("no baseline in");
    expect(result.pending).toHaveLength(2);
    expect(migrate).toHaveBeenCalledOnce();
    expect(world.log).toContain(
      "Running the seed files: no baseline was loaded",
    );
    expect(world.log).toContain("Seeding supabase/seeds/a.sql");
    expect(uploads.calls).toHaveLength(2);
    expect(uploads.calls[0]?.headers.get("authorization")).toBe(
      "Bearer secret",
    );
  });

  it("loads the baseline and the seed snapshot when nothing changed", async () => {
    const built = await build(true);

    const migrate = vi.fn(() =>
      Promise.resolve({ code: 0, stdout: "", stderr: "" }),
    );

    const result = await apply(true, migrate);

    expect(result).toMatchObject({
      mode: "baseline",
      key: built.key,
      pending: [],
      seed: "snapshot",
    });
    expect(result.reason).toBeUndefined();
    expect(migrate).not.toHaveBeenCalled();
    expect(
      uploads.calls
        .map((call) => call.headers.get("content-type") ?? "")
        .toSorted((a, b) => a.localeCompare(b)),
    ).toEqual(["image/png", "text/plain"]);
  });

  it("runs the newer migrations, then the seed files, on top of the baseline", async () => {
    await build(true);
    await writeFile(
      join(world.root, "supabase/migrations/20240103000000_more.sql"),
      "select 3;\n",
    );

    const migrate = vi.fn(() =>
      Promise.resolve({ code: 0, stdout: "", stderr: "" }),
    );

    const result = await apply(true, migrate);

    expect(result).toMatchObject({
      mode: "baseline",
      pending: ["20240103000000_more.sql"],
      seed: "files",
    });
    expect(migrate).toHaveBeenCalledOnce();
    expect(world.log).toContain(
      "Running the seed files: migrations newer than the baseline would run before the seeds",
    );
  });

  it("replays a database that already has migrations", async () => {
    await build(false);
    world.dbs.set("54322", MIGRATED);

    const result = await apply(false);

    expect(result).toMatchObject({
      mode: "replay",
      reason: "the database already has 2 applied migrations",
      seed: "none",
    });
  });

  it("falls back to a replay when the load fails", async () => {
    await build(false);
    world.failLoad = true;

    const result = await apply(false);

    expect(result.mode).toBe("replay");
    expect(result.reason).toBe(
      "loading the baseline failed (psql failed: line 1 line 2 ERROR: boom)",
    );
    expect(world.log).toContain(`Not using a baseline: ${result.reason}`);
  });

  it("stops when supabase migration up fails", async () => {
    await expect(
      apply(false, () =>
        Promise.resolve({ code: 1, stdout: "drift", stderr: "" }),
      ),
    ).rejects.toThrow("supabase migration up failed: drift");
  });

  it("needs a Storage API for the bucket objects", async () => {
    await expect(
      applyBaseline(world.ctx, {
        withSeed: true,
        target: {
          dbUrl: world.localUrl,
          migrate: () => Promise.resolve({ code: 0, stdout: "", stderr: "" }),
        },
      }),
    ).rejects.toThrow("no Storage API URL or service key");
  });

  it("reports a failed upload", async () => {
    vi.stubGlobal(
      "fetch",
      fakeFetch(() => ({ status: 403, text: "denied" })).fetch,
    );

    await expect(apply(true)).rejects.toThrow(
      /Uploading avatars\/.* failed with 403: denied/,
    );
  });
});

describe("baseline verify", () => {
  it("restores the artifact and finds it equal to the replay", async () => {
    const built = await build(true);

    await expect(
      verifyBaseline(world.ctx, { withSeed: true }),
    ).resolves.toEqual({
      key: built.key,
      schemaActions: 0,
      fingerprintMatches: true,
      mismatchedCounts: [],
    });
    await expect(
      verifyBaseline(world.ctx, { withSeed: false }),
    ).resolves.toMatchObject({ key: built.key });
  });

  it("needs a baseline that covers the migrations", async () => {
    await expect(
      verifyBaseline(world.ctx, { withSeed: false }),
    ).rejects.toThrow(
      "No baseline covers the current migrations: no baseline in",
    );
  });

  it("reports a baseline that does not load", async () => {
    await build(false);
    world.failLoad = true;

    await expect(
      verifyBaseline(world.ctx, { withSeed: false }),
    ).rejects.toThrow("The baseline did not load: loading the baseline failed");
  });

  it("lists every difference from the replay", async () => {
    const built = await build(false);
    const files = artifactFiles(baselineRoot(world.root), built.key);
    const manifest = JSON.parse(await readFile(files.manifest, "utf-8"));

    await writeFile(
      files.manifest,
      JSON.stringify({
        ...manifest,
        counts: { ...manifest.counts, "public.plans": 5, "public.gone": 1 },
        fingerprint: { ...manifest.fingerprint, policies: "other" },
      }),
    );
    await writeFile(
      files.snapshot,
      JSON.stringify({
        facts: {
          catalog: "edited",
          edges: [
            { kind: "memberOfExtension", from: "table:extensions.lookup" },
          ],
        },
        pgVersion: "170006",
      }),
    );

    const error = await verifyBaseline(world.ctx, { withSeed: false }).catch(
      (cause: unknown) => cause,
    );

    expect(String(error)).toContain(
      "pg-delta still plans 2 action(s), e.g. create table edited ();",
    );
    expect(String(error)).toContain("the policies differ");
    expect(String(error)).toContain(
      "row counts differ in public.plans (5 expected, 2 restored), public.gone (1 expected, missing restored)",
    );
  });
});
