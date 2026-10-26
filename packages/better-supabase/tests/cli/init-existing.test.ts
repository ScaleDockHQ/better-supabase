import { cp, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { resolveConfig } from "../../src/config/index.ts";

const snapshotFixture = join(
  import.meta.dirname,
  "fixtures/module-snapshot.json",
);

vi.mock(import("../../src/cli/commands/snapshot.ts"), async (original) => ({
  ...(await original()),
  loadSnapshot: vi.fn(async (_config, _env, source) => {
    const real = await original();

    return real.loadSnapshot(_config, _env, {
      snapshotPath: source.snapshotPath ?? snapshotFixture,
    });
  }),
}));

const {
  detectExisting,
  existingLines,
  isDatabaseUrl,
  planSnapshotFrom,
  SNAPSHOT_PATH,
} = await import("../../src/cli/init-existing.ts");

const { run } = await import("../../src/cli/core/run.ts");

describe("init on an existing project", () => {
  let dir: string;

  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), "better-supabase-init-existing-"));
  });

  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  async function supabaseFolder(): Promise<void> {
    await mkdir(join(dir, "supabase/migrations"), { recursive: true });
    await mkdir(join(dir, "supabase/schemas/nested"), { recursive: true });
    await writeFile(join(dir, "supabase/migrations/1_a.sql"), "select 1;");
    await writeFile(join(dir, "supabase/migrations/2_b.sql"), "select 2;");
    await writeFile(join(dir, "supabase/schemas/nested/t.sql"), "select 3;");
  }

  it("tells a url from a preset", () => {
    expect(isDatabaseUrl("postgresql://u:p@h:5432/db")).toBe(true);
    expect(isDatabaseUrl("postgres://h/db")).toBe(true);
    expect(isDatabaseUrl("crm")).toBe(false);
  });

  it("finds nothing without a supabase folder", async () => {
    expect(
      await detectExisting(resolveConfig({}, dir), {}, dir),
    ).toBeUndefined();
  });

  it("counts migrations, schema files and snapshot tables", async () => {
    await supabaseFolder();
    await cp(snapshotFixture, join(dir, SNAPSHOT_PATH));

    const found = await detectExisting(resolveConfig({}, dir), {}, dir);

    expect(found?.migrations).toBe(2);
    expect(found?.schemaFiles).toBe(1);
    expect(found?.tables.length).toBeGreaterThan(0);
    expect(existingLines(found!).join("\n")).toContain(
      "Found an existing Supabase project: 2 migration(s), 1 schema file(s)",
    );
  });

  it("treats an unreadable snapshot as no tables", async () => {
    await supabaseFolder();
    await writeFile(join(dir, SNAPSHOT_PATH), "not json");

    const found = await detectExisting(resolveConfig({}, dir), {}, dir);

    expect(found?.tables).toEqual([]);
  });

  it("plans the snapshot read from a database url", async () => {
    const { plan, tables } = await planSnapshotFrom(
      resolveConfig({}, dir),
      {},
      dir,
      "postgresql://postgres:postgres@127.0.0.1:54322/postgres",
    );

    expect(tables).toBeGreaterThan(0);
    expect(plan.files[0]?.path).toBe(join(dir, SNAPSHOT_PATH));
    expect(plan.files[0]?.contents).toContain("snapshot-v2.json");
  });

  it("reports the project and writes the snapshot through init --from", async () => {
    await supabaseFolder();
    await writeFile(join(dir, "package.json"), '{"name":"app"}');

    const result = await run([
      "init",
      "--from",
      "postgresql://postgres:postgres@127.0.0.1:54322/postgres",
      "--cwd",
      dir,
      "--yes",
    ]);

    expect(result.code).toBe(0);
    expect(result.stdout).toContain("Found an existing Supabase project");
    expect(result.stdout).toContain("better-supabase doctor");
    expect(await readFile(join(dir, SNAPSHOT_PATH), "utf-8")).toContain(
      "snapshot-v2.json",
    );
  });

  it("treats a --from that is not a url as --preset, and refuses both", async () => {
    await writeFile(join(dir, "package.json"), '{"name":"app"}');

    const both = await run([
      "init",
      "--from",
      "crm",
      "--preset",
      "crm",
      "--cwd",
      dir,
    ]);

    expect(both.code).toBe(2);
    expect(both.stderr).toContain("--from or --preset");

    const preset = await run(["init", "--from", "crm", "--cwd", dir, "--yes"]);

    expect(preset.code).toBe(0);
  });
});
