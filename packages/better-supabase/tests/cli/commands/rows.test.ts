import { mkdir, mkdtemp, readdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { dbRowsCommand } from "../../../src/cli/commands/rows.ts";
import { CliError } from "../../../src/cli/core/errors.ts";
import { resolveConfig } from "../../../src/config/index.ts";

interface Result {
  code: number;
  output?: string;
  error?: string;
  errorCode?: string;
  data?: { migrations: string[]; current: string[]; review: string[] };
}

const upsert = (...keys: string[]): string =>
  `insert into public.flags (key, on_by_default) values ${keys.map((key) => `('${key}', true)`).join(", ")} on conflict (key) do update set on_by_default = excluded.on_by_default;\n`;

async function project(rows?: Record<string, string>) {
  const root = await mkdtemp(join(tmpdir(), "rows-"));
  await mkdir(join(root, "supabase"), { recursive: true });
  await writeFile(join(root, "supabase", "config.toml"), "");

  if (rows !== undefined) {
    await mkdir(join(root, "supabase", "rows"), { recursive: true });

    for (const [file, text] of Object.entries(rows)) {
      await writeFile(join(root, "supabase", "rows", file), text);
    }
  }

  const config = resolveConfig(
    { database: { sql: { dir: "supabase" } } },
    root,
  );

  const command = dbRowsCommand as unknown as {
    run: (input: { args: object; data: unknown }) => Promise<Result>;
  };

  const run = (args: object = {}) =>
    command.run({
      args,
      data: { cwd: root, config, io: {}, env: {}, json: false },
    });

  const migrations = () =>
    readdir(join(root, "supabase", "migrations")).catch((): string[] => []);

  return { root, run, migrations };
}

describe("db rows", () => {
  it("has nothing to sync without rows files", async () => {
    const { run } = await project({ "notes.txt": "skip me" });

    expect(await run()).toEqual({
      code: 0,
      output: "supabase/rows has no rows files, so there is nothing to sync.",
      data: { migrations: [], current: [], review: [] },
    });
  });

  it("writes a migration once, then reports every file current", async () => {
    const { run, migrations } = await project({ "flags.sql": upsert("a") });

    const dry = await run({ "dry-run": true });

    expect(dry.output).toMatch(
      /^Would write supabase\/migrations\/\d{14}_declared_rows_flags_/,
    );
    expect(await migrations()).toEqual([]);

    const pending = await run({ check: true });

    expect(pending).toMatchObject({ code: 1, errorCode: "check_failed" });
    expect(pending.error).toMatch(
      /^flags\.sql needs supabase\/migrations\/.+\. Run `better-supabase db rows`\.$/,
    );

    const wrote = await run();

    expect(wrote.output).toMatch(/^Wrote supabase\/migrations\//);
    expect(await migrations()).toEqual(wrote.data?.migrations);

    expect(await run()).toMatchObject({
      code: 0,
      output: "Every rows file already has its data migration.",
      data: { migrations: [], current: ["flags"] },
    });
    expect(await run({ check: true })).toMatchObject({
      code: 0,
      output: "Every rows file in supabase/rows has its data migration.",
    });
  });

  it("prints a review line for a removed row", async () => {
    const { root, run } = await project({ "flags.sql": upsert("a", "b") });
    await run();
    await writeFile(join(root, "supabase", "rows", "flags.sql"), upsert("a"));

    const result = await run();

    expect(result.output?.split("\n")[1]).toMatch(
      /^review: flags: public\.flags \(b\) is removed/,
    );
    expect(result.data?.review).toHaveLength(1);
  });

  it("turns a rows file that is not an upsert into invalid input", async () => {
    const { run } = await project({ "bad.sql": "delete from t;" });

    await expect(run()).rejects.toThrow(CliError);
    await expect(run()).rejects.toMatchObject({ code: "invalid_input" });
  });

  it("passes a parse error through unchanged", async () => {
    const { run } = await project({ "broken.sql": "insert into (" });
    const error = await run().catch((cause: unknown) => cause);

    expect(error).toBeInstanceOf(Error);
    expect(error).not.toBeInstanceOf(CliError);
  });
});
