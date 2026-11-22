import { execFile } from "node:child_process";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { parseValue } from "./set-config-value.ts";

const run = promisify(execFile);

describe("parseValue", () => {
  it("reads JSON scalars and string lists, and a bare word as a string", () => {
    expect(parseValue('["./seed.sql"]')).toEqual(["./seed.sql"]);
    expect(parseValue("true")).toBe(true);
    expect(parseValue("7")).toBe(7);
    expect(parseValue("./seed.sql")).toBe("./seed.sql");
    expect(parseValue("[1]")).toBe("[1]");
  });
});

describe("set-config-value", () => {
  let dir: string;

  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), "set-config-"));
    await mkdir(join(dir, "supabase"));
  });

  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  it.each([
    ["config.toml", '[db.seed]\n# keep\nsql_paths = ["./a.sql", "./b.sql"]\n'],
    [
      "config.jsonc",
      '{ "db": { "seed": { /* keep */ "sql_paths": ["./a.sql", "./b.sql"] } } }\n',
    ],
  ])("rewrites sql_paths in %s and keeps its comment", async (name, text) => {
    await writeFile(join(dir, "supabase", name), text);

    await run("node", [
      "scripts/set-config-value.ts",
      dir,
      "db.seed.sql_paths",
      '["./seed.sql"]',
    ]);

    const written = await readFile(join(dir, "supabase", name), "utf-8");

    expect(written).toContain("./seed.sql");
    expect(written).not.toContain("./b.sql");
    expect(written).toContain("keep");
  });
});
