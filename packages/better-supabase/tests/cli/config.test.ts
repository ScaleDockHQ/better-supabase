import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { discoverConfig, loadConfig } from "../../src/cli/config.ts";
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
