import {
  mkdir,
  mkdtemp,
  readdir,
  readFile,
  rm,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import {
  dbSquashCommand,
  runSquash,
} from "../../../src/cli/commands/squash.ts";
import { parseCommandArgs } from "../../../src/cli/core/command.ts";
import { resolveConfig } from "../../../src/config/index.ts";

const args = (argv: string[]) => parseCommandArgs(dbSquashCommand, argv);

async function project(): Promise<{ root: string; dir: string }> {
  const root = await mkdtemp(join(tmpdir(), "squash-"));
  const dir = join(root, "supabase", "migrations");
  await mkdir(dir, { recursive: true });
  await writeFile(join(root, "supabase", "config.toml"), "");

  const files: Record<string, string> = {
    "20260101000000_better_supabase_extensions.sql": "create extension a;",
    "20260102000000_init.sql": "create table t();",
    "20260103000000_reference_data.sql": "insert 1;",
    "20260104000000_add_col.sql": "alter table t add c int;",
    "20260105000000_reference_data.sql": "insert 2;",
  };

  for (const [file, text] of Object.entries(files)) {
    await writeFile(join(dir, file), text);
  }

  return { root, dir };
}

const ok = { code: 0, stdout: "", stderr: "" };

describe("db squash", () => {
  it("writes the baseline between the extensions and the kept data", async () => {
    const { root, dir } = await project();
    const calls: string[][] = [];

    const result = await runSquash(
      resolveConfig({ database: { sql: { dir: "supabase" } } }, root),
      args(["--keep", "reference_data"]),
      {},
      {
        now: () => new Date("2026-06-01T00:00:10Z"),
        supabase: async (argv, cwd) => {
          calls.push([...argv]);
          await writeFile(
            join(cwd, "supabase/migrations/20260601000010_init.sql"),
            "baseline",
          );

          return ok;
        },
      },
    );

    expect(result.code).toBe(0);
    expect(calls[0]).toContain("--no-apply");
    expect(await readdir(dir)).toEqual([
      "20260601000008_better_supabase_extensions.sql",
      "20260601000010_init.sql",
      "20260601000011_reference_data.sql",
    ]);
    expect(
      await readFile(join(dir, "20260601000011_reference_data.sql"), "utf-8"),
    ).toBe("insert 1;\ninsert 2;");
  });

  it("stamps kept data after the baseline even when the baseline is stamped later than the clock", async () => {
    const { root, dir } = await project();

    await runSquash(
      resolveConfig({ database: { sql: { dir: "supabase" } } }, root),
      args(["--keep", "reference_data"]),
      {},
      {
        now: () => new Date("2026-06-01T00:00:10Z"),
        supabase: async (_argv, cwd) => {
          await writeFile(
            join(cwd, "supabase/migrations/20260601000030_init.sql"),
            "baseline",
          );

          return ok;
        },
      },
    );

    expect(await readdir(dir)).toContain("20260601000031_reference_data.sql");
  });

  it("carries a kept migration pg-delta wrote as several files, in numeric order", async () => {
    const { root, dir } = await project();

    await rm(join(dir, "20260103000000_reference_data.sql"));
    await rm(join(dir, "20260105000000_reference_data.sql"));

    for (const n of [1, 10, 2]) {
      await writeFile(
        join(dir, `20260106000000_reference_data_${String(n)}.sql`),
        `-- pg-delta: transaction=false\nselect ${String(n)};`,
      );
    }

    const result = await runSquash(
      resolveConfig({ database: { sql: { dir: "supabase" } } }, root),
      args(["--keep", "reference_data"]),
      {},
      {
        now: () => new Date("2026-06-01T00:00:10Z"),
        supabase: async (_argv, cwd) => {
          await writeFile(
            join(cwd, "supabase/migrations/20260601000010_init.sql"),
            "baseline",
          );

          return ok;
        },
      },
    );

    expect(result.code).toBe(0);
    expect(
      await readFile(join(dir, "20260601000011_reference_data.sql"), "utf-8"),
    ).toBe("-- pg-delta: transaction=false\nselect 1;\nselect 2;\nselect 10;");
  });

  it("names the pg-delta-only feature under migra", async () => {
    const { root } = await project();

    await writeFile(
      join(root, "supabase", "config.toml"),
      '[db.migrations]\nschema_paths = ["./schemas/*.sql"]\n',
    );

    await expect(
      runSquash(
        resolveConfig({ database: { sql: { dir: "supabase" } } }, root),
        args([]),
        {},
      ),
    ).rejects.toMatchObject({
      code: "usage",
      message: expect.stringContaining("db squash"),
    });
  });

  it("refuses to join kept files that disagree about transaction=false", async () => {
    const { root, dir } = await project();

    await writeFile(
      join(dir, "20260106000000_reference_data_1.sql"),
      "-- pg-delta: transaction=false\nselect 1;",
    );
    await writeFile(
      join(dir, "20260106000000_reference_data_2.sql"),
      "select 2;",
    );

    await expect(
      runSquash(
        resolveConfig({ database: { sql: { dir: "supabase" } } }, root),
        args(["--keep", "reference_data"]),
        {},
        { now: () => new Date(), supabase: () => Promise.resolve(ok) },
      ),
    ).rejects.toMatchObject({ code: "usage" });
  });

  it("restores the migrations when the baseline fails", async () => {
    const { root, dir } = await project();

    const result = await runSquash(
      resolveConfig({ database: { sql: { dir: "supabase" } } }, root),
      args([]),
      {},
      { supabase: async () => ({ code: 1, stdout: "", stderr: "boom" }) },
    ).catch((error: unknown) => error);

    expect(String(result)).toContain("boom");
    expect(await readdir(dir)).toHaveLength(5);
  });

  it("changes nothing with --dry-run and rejects an unknown --keep name", async () => {
    const { root, dir } = await project();

    const config = resolveConfig(
      { database: { sql: { dir: "supabase" } } },
      root,
    );

    const dry = await runSquash(config, args(["--dry-run"]), {});

    expect(dry.code).toBe(0);
    expect(await readdir(dir)).toHaveLength(5);

    await expect(
      runSquash(config, args(["--keep", "nope"]), {}),
    ).rejects.toMatchObject({ code: "not_found" });
  });
});

describe("db squash edges", () => {
  const config = (root: string) =>
    resolveConfig({ database: { sql: { dir: "supabase" } } }, root);

  it("rejects a bad --name and an empty migrations folder", async () => {
    const root = await mkdtemp(join(tmpdir(), "squash-empty-"));

    await expect(
      runSquash(config(root), args(["--name", "bad-name"]), {}),
    ).rejects.toMatchObject({ code: "invalid_value" });
    await expect(runSquash(config(root), args([]), {})).rejects.toMatchObject({
      code: "not_found",
    });
  });

  it("carries nothing over without an extensions migration", async () => {
    const root = await mkdtemp(join(tmpdir(), "squash-plain-"));
    const dir = join(root, "supabase", "migrations");

    await mkdir(dir, { recursive: true });
    await writeFile(join(dir, "20260102000000_init.sql"), "create table t();");

    const dry = await runSquash(config(root), args(["--dry-run"]), {});

    expect(dry.output).toBe(
      "Would replace 1 migrations in supabase/migrations with init and carry over nothing.",
    );

    const result = await runSquash(
      config(root),
      args(["--name", "base"]),
      {},
      { supabase: async () => ok },
    );

    expect(result.output).toBe(
      "Replaced 1 migrations in supabase/migrations with base. Reset the database to apply it.",
    );
  });

  it("names stdout when the CLI fails without stderr", async () => {
    const { root } = await project();

    await expect(
      runSquash(
        config(root),
        args([]),
        {},
        { supabase: async () => ({ code: 2, stdout: "out ", stderr: " " }) },
      ),
    ).rejects.toThrow("supabase db schema declarative sync failed (2): out");
  });

  it("restores the migrations and returns a failure for an unexpected error", async () => {
    const { root, dir } = await project();

    await writeFile(join(dir, "README.md"), "notes");

    const result = await runSquash(
      config(root),
      args([]),
      {},
      {
        supabase: async () => {
          throw new Error("spawn failed");
        },
      },
    );

    expect(result).toEqual({
      code: 1,
      errorCode: "failed",
      error: "db squash failed and restored the migrations: spawn failed",
    });
    expect(await readdir(dir)).toHaveLength(6);
  });
});
