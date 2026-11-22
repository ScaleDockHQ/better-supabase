import { mkdir, mkdtemp, readdir, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { applyPlan, ExclusiveClash } from "../../../src/cli/core/files.ts";
import { writeMigration } from "../../../src/cli/sql/migration-write.ts";
import { resolveConfig } from "../../../src/config/index.ts";

async function project(): Promise<{ root: string; dir: string }> {
  const root = await mkdtemp(join(tmpdir(), "migration-write-"));
  const dir = join(root, "supabase", "migrations");

  await mkdir(dir, { recursive: true });
  await writeFile(join(root, "supabase", "config.toml"), "");

  return { root, dir };
}

describe("exclusive files", () => {
  it("throws ExclusiveClash instead of replacing a file another process wrote", async () => {
    const { root, dir } = await project();
    const path = join(dir, "20260601000000_x.sql");

    await writeFile(path, "theirs");

    await expect(
      applyPlan(
        {
          root,
          regenerate: "x",
          files: [
            { path, contents: "ours", policy: "generated", exclusive: true },
          ],
        },
        { force: true },
      ),
    ).rejects.toBeInstanceOf(ExclusiveClash);
    expect(await readFile(path, "utf-8")).toBe("theirs");
  });
});

describe("writeMigration", () => {
  it("stamps after the files in the folder, including pg-delta's multi-file output", async () => {
    const { root, dir } = await project();

    for (const name of ["20260601000000_a_1.sql", "20260601000000_a_2.sql"]) {
      await writeFile(join(dir, name), "x");
    }

    const { path } = await writeMigration(
      resolveConfig({ database: { sql: { dir: "supabase" } } }, root),
      {
        dir: "supabase/migrations",
        now: () => new Date("2026-06-01T00:00:00Z"),
        suffix: "_data.sql",
        contents: "select 1;",
        regenerate: "x",
        flags: {},
      },
    );

    expect(path.startsWith("supabase/migrations/20260601000001_data_")).toBe(
      true,
    );
    expect(await readdir(dir)).toHaveLength(3);
  });
});

describe("ExclusiveClash", () => {
  it("names the path", () => {
    expect(new ExclusiveClash("/a").message).toContain("/a");
  });
});
