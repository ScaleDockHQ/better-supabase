import { existsSync } from "node:fs";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { run } from "../../src/cli/core/run.ts";

let dir: string;

beforeEach(async () => {
  dir = await mkdtemp(join(tmpdir(), "better-supabase-init-branches-"));
});

afterEach(async () => {
  await rm(dir, { recursive: true, force: true });
});

async function project(dependencies: Record<string, string>): Promise<void> {
  await writeFile(
    join(dir, "package.json"),
    JSON.stringify({ name: "app", dependencies }),
  );
  await writeFile(join(dir, "pnpm-lock.yaml"), "");
}

describe("init options", () => {
  it("rejects a workflow it does not know", async () => {
    await project({});

    const result = await run(["init", "--workflow", "bogus", "--cwd", dir]);

    expect(result.code).toBe(2);
    expect(result.stderr).toContain(
      '--workflow must be "pg-delta", "migra" or "migrations"',
    );
    expect(existsSync(join(dir, "better-supabase.config.ts"))).toBe(false);
  });

  it("rejects an integration it does not know", async () => {
    await project({});

    const result = await run([
      "init",
      "--integration",
      "not-an-integration",
      "--cwd",
      dir,
    ]);

    expect(result.code).toBe(2);
    expect(existsSync(join(dir, "better-supabase.config.ts"))).toBe(false);
  });

  it("does not ask for dev packages the project already has", async () => {
    await project({
      "@supabase/lite": "0.11.0",
      "@supabase/postgrest-typegen": "1.0.0",
    });

    const result = await run(["init", "--lite", "--cwd", dir]);

    expect(result.code).toBe(0);
    expect(result.stdout).not.toContain("pnpm add -D");
  });

  it("asks for only the missing one of the two", async () => {
    await project({ pg: "8.0.0" });

    const result = await run(["init", "--cwd", dir]);

    expect(result.stderr).toContain("pnpm add -D @supabase/postgrest-typegen@");
    expect(result.stderr).not.toContain("-D pg");
  });

  it("writes nothing on a dry run", async () => {
    await project({});

    const result = await run(["init", "--dry-run", "--cwd", dir]);

    expect(result.code).toBe(0);
    expect(existsSync(join(dir, "better-supabase.config.ts"))).toBe(false);
  });

  it("reports drift in check mode instead of writing", async () => {
    await project({});

    const result = await run(["init", "--check", "--cwd", dir]);

    expect(result.code).not.toBe(2);
    expect(existsSync(join(dir, "better-supabase.config.ts"))).toBe(false);
  });
});

describe("init and the SQL workflow", () => {
  const toml = async (text: string): Promise<void> => {
    await mkdir(join(dir, "supabase"), { recursive: true });
    await writeFile(join(dir, "supabase/config.toml"), text);
  };

  it("leaves a config.toml that lists schema_paths alone", async () => {
    await project({});

    const text = '[db.migrations]\nschema_paths = ["./schemas/*.sql"]\n';

    await toml(text);

    const result = await run(["init", "--yes", "--cwd", dir]);

    expect(result.code).toBe(0);
    expect(result.stdout).toContain("Skipped supabase/config.toml");
    expect(await readFile(join(dir, "supabase/config.toml"), "utf-8")).toBe(
      text,
    );
  });

  it("turns pg-delta on when config.toml says nothing about the engine", async () => {
    await project({});
    await toml("[api]\nenabled = true\n");

    const result = await run(["init", "--yes", "--cwd", dir]);

    expect(result.code).toBe(0);
    expect(
      await readFile(join(dir, "supabase/config.toml"), "utf-8"),
    ).toContain("[experimental.pgdelta]");
  });
});
