import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { databaseUrl } from "../../src/cli/config.ts";
import { resolveConfig } from "../../src/config/index.ts";

describe("databaseUrl with a named stack", () => {
  let root: string;

  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "better-supabase-stack-"));
    await mkdir(join(root, "supabase/stacks/tests"), { recursive: true });
    await writeFile(join(root, "supabase/config.toml"), "[db]\nport = 54322\n");

    await writeFile(
      join(root, "supabase/stacks/tests/config.toml"),
      "[db]\nport = 54422\n",
    );
  });

  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
  });

  it("reads the port of that stack", async () => {
    const config = resolveConfig({}, root);

    expect(await databaseUrl(config, {}, undefined, "tests")).toBe(
      "postgresql://postgres:postgres@127.0.0.1:54422/postgres",
    );
  });

  it("reads $BSB_STACK when no stack is passed", async () => {
    const config = resolveConfig({}, root);

    expect(await databaseUrl(config, { BSB_STACK: "tests" })).toContain(
      ":54422/",
    );
  });

  it("rejects an unknown or unsafe stack", async () => {
    const config = resolveConfig({}, root);

    await expect(databaseUrl(config, {}, undefined, "demo")).rejects.toThrow(
      'The stack "demo"',
    );

    await expect(databaseUrl(config, {}, undefined, "../x")).rejects.toThrow(
      "must be lowercase",
    );
  });

  it("keeps a connection string over a stack", async () => {
    const config = resolveConfig({}, root);

    expect(
      await databaseUrl(
        config,
        { DATABASE_URL: "postgresql://u@h/d" },
        undefined,
        "tests",
      ),
    ).toBe("postgresql://u@h/d");
  });
});
