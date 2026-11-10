import { mkdir, mkdtemp, readdir, readFile, writeFile } from "node:fs/promises";
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
