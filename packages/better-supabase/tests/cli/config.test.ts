import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import {
  applyEnvironment,
  discoverConfig,
  loadConfig,
} from "../../src/cli/config.ts";
import { configEnvironment } from "../../src/cli/env.ts";
import { run } from "../../src/cli/run.ts";
import { findRepoRoot } from "../../src/cli/supabase-toml.ts";

describe("config discovery", () => {
  let repo: string;
  let pkg: string;

  beforeEach(async () => {
    repo = await mkdtemp(join(tmpdir(), "better-supabase-config-"));
    pkg = join(repo, "packages/runtime");
    await mkdir(join(repo, ".git"));
    await mkdir(join(pkg, "src"), { recursive: true });
  });

  afterEach(async () => {
    await rm(repo, { recursive: true, force: true });
  });

  const write = (dir: string, name: string, contents: object) =>
    writeFile(join(dir, name), JSON.stringify(contents));

  it("loads the config at the repository root from a nested package", async () => {
    await write(repo, "better-supabase.config.json", {
      output: "packages/runtime/src/generated.ts",
      casing: "camel",
    });
    const config = await loadConfig(join(pkg, "src"));
    expect(config.root).toBe(repo);
    expect(config.output).toBe("packages/runtime/src/generated.ts");
    expect(config.casing).toBe("camel");
  });

  it("prefers the nearest config", async () => {
    await write(repo, "better-supabase.config.json", { casing: "camel" });
    await write(pkg, "better-supabase.config.json", { casing: "snake" });
    const config = await loadConfig(pkg);
    expect(config.root).toBe(pkg);
    expect(config.casing).toBe("snake");
  });

  it("does not look past the .git boundary", async () => {
    const outer = await mkdtemp(join(tmpdir(), "better-supabase-outer-"));

    try {
      await write(outer, "better-supabase.config.json", { casing: "camel" });
      const inner = join(outer, "checkout/app");
      await mkdir(join(outer, "checkout/.git"), { recursive: true });
      await mkdir(inner, { recursive: true });
      expect(discoverConfig(inner)).toBeUndefined();
      expect((await loadConfig(inner)).root).toBe(inner);
    } finally {
      await rm(outer, { recursive: true, force: true });
    }
  });

  it("keeps --config relative to the working directory", async () => {
    await write(repo, "better-supabase.config.json", { casing: "camel" });
    await write(pkg, "other.json", { casing: "snake" });
    const config = await loadConfig(pkg, "other.json");
    expect(config.root).toBe(pkg);
    expect(config.casing).toBe("snake");
    expect(discoverConfig(pkg, "other.json")).toBe(join(pkg, "other.json"));
  });

  it("finds the repository root from .git, else the project root", async () => {
    expect(findRepoRoot(pkg)).toBe(repo);
    await rm(join(repo, ".git"), { recursive: true });
    await mkdir(join(repo, "supabase"));
    await writeFile(join(repo, "supabase/config.toml"), "");
    expect(findRepoRoot(pkg)).toBe(repo);
  });
});

describe("config environments", () => {
  let dir: string;

  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), "better-supabase-env-"));
    await writeFile(
      join(dir, "better-supabase.config.json"),
      JSON.stringify({
        casing: "camel",
        doctor: { ignore: ["BS100"], strict: false },
        gen: { tasks: ["types", "spec"] },
        $env: { staging: { doctor: { strict: true } } },
        $ci: {
          doctor: {
            format: "sarif",
            output: "doctor.sarif",
            ignore: ["BS304"],
          },
          gen: { tasks: ["types"] },
        },
      }),
    );
  });

  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  it("applies no block without an environment", async () => {
    const config = await loadConfig(dir);
    expect(config.environment).toBeUndefined();
    expect(config.doctor.format).toBe("text");
    expect(config.gen.tasks).toEqual(["types", "spec"]);
  });

  it("merges objects and replaces arrays", async () => {
    const config = await loadConfig(dir, undefined, "ci");
    expect(config.environment).toBe("ci");
    expect(config.casing).toBe("camel");
    expect(config.doctor).toMatchObject({
      format: "sarif",
      output: "doctor.sarif",
      ignore: ["BS304"],
      strict: false,
    });
    expect(config.gen.tasks).toEqual(["types"]);
  });

  it("reads a named block from $env", async () => {
    const config = await loadConfig(dir, undefined, "staging");
    expect(config.doctor.strict).toBe(true);
    expect(config.doctor.ignore).toEqual(["BS100"]);
  });

  it("keeps the base for an environment with no block", async () => {
    const config = await loadConfig(dir, undefined, "preview");
    expect(config.environment).toBe("preview");
    expect(config.doctor.strict).toBe(false);
  });

  it("rejects a block that makes the config invalid", () => {
    expect(() =>
      applyEnvironment({ $test: { gen: { watchInterval: 0 } } }, "test"),
    ).toThrow("The test environment makes the config invalid");
  });

  it("points sql.modules at the 0.9 codemod", async () => {
    await writeFile(
      join(dir, "better-supabase.config.json"),
      JSON.stringify({
        sql: { modules: ["tenant"] },
        $production: { sql: { modules: { tenant: true } } },
      }),
    );

    const error = await loadConfig(dir).catch((error: unknown) => error);
    expect(error).toMatchObject({
      code: "config_invalid",
      message: expect.stringContaining(
        "sql.modules: moved to the top-level `blocks` key in 0.9; run `better-supabase codemod 0.9`",
      ),
    });
    expect(error).toMatchObject({
      message: expect.stringContaining("$production.sql.modules: moved"),
    });
    expect(() =>
      // @ts-expect-error -- `sql.modules` is the removed 0.8 key under test.
      applyEnvironment({ $test: { sql: { modules: ["tenant"] } } }, "test"),
    ).toThrow("sql.modules: moved to the top-level `blocks` key");
  });

  it("picks --env, then $BETTER_SUPABASE_ENV, then ci in CI", () => {
    expect(
      configEnvironment("staging", { BETTER_SUPABASE_ENV: "x", CI: "1" }),
    ).toBe("staging");
    expect(
      configEnvironment(undefined, { BETTER_SUPABASE_ENV: "x", CI: "1" }),
    ).toBe("x");
    expect(configEnvironment(undefined, { CI: "true" })).toBe("ci");
    expect(configEnvironment(undefined, { CI: "false" })).toBeUndefined();
    expect(configEnvironment(undefined, {})).toBeUndefined();
  });

  it("prints the active environment", async () => {
    const result = await run(["config", "--env", "ci", "--cwd", dir], {
      env: {},
    });

    expect(result.code).toBe(0);
    expect(result.stdout).toMatch(
      /^# better-supabase\.config\.json \(environment: ci\)/,
    );
    expect(result.stdout).toContain('"format": "sarif"');
  });
});
