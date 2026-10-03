import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import {
  detectProject,
  installCommand,
  type PackageManager,
  type Project,
  publicPrefix,
} from "../../src/cli/project.ts";

describe("detectProject", () => {
  let root: string;

  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "better-supabase-project-"));
  });

  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
  });

  const write = (path: string, contents = "") =>
    writeFile(join(root, path), contents);

  it("reads an empty directory with defaults", async () => {
    expect(await detectProject(root)).toEqual({
      root,
      name: undefined,
      frameworks: [],
      packageManager: "pnpm",
      dependencies: {},
      srcDir: ".",
      tsExtensions: false,
      hasSupabase: false,
    });
  });

  it("reads package.json, a commented tsconfig, src and supabase", async () => {
    await write(
      "package.json",
      JSON.stringify({
        name: "app",
        packageManager: "yarn@4.0.0",
        dependencies: { next: "16.0.0", vite: "7" },
        devDependencies: { "@tanstack/react-query": "5" },
        peerDependencies: { expo: "54", hono: "4" },
      }),
    );
    await write(
      "tsconfig.json",
      '{\n  // comment\n  "compilerOptions": { "rewriteRelativeImportExtensions": true, },\n}\n',
    );
    await mkdir(join(root, "src"));
    await mkdir(join(root, "supabase"));
    await write("supabase/config.toml");
    const project = await detectProject(root);
    expect(project).toMatchObject({
      name: "app",
      frameworks: ["next", "hono", "vite", "expo", "tanstack-query"],
      packageManager: "yarn",
      srcDir: "src",
      tsExtensions: true,
      hasSupabase: true,
    });
    expect(project.dependencies["@tanstack/react-query"]).toBe("5");
  });

  it("treats unreadable JSON as missing", async () => {
    await write("package.json", "{ nope");
    await write("tsconfig.json", "[");
    expect(await detectProject(root)).toMatchObject({
      name: undefined,
      tsExtensions: false,
    });
  });

  it.each([
    ["pnpm-lock.yaml", "pnpm"],
    ["bun.lock", "bun"],
    ["bun.lockb", "bun"],
    ["yarn.lock", "yarn"],
    ["package-lock.json", "npm"],
  ] as const)("detects the package manager from %s", async (lock, manager) => {
    await write(lock);
    expect((await detectProject(root)).packageManager).toBe(manager);
  });

  it("falls back to lock files for an unknown packageManager and reads allowImportingTsExtensions", async () => {
    await write(
      "package.json",
      JSON.stringify({ packageManager: "deno@2", name: 1 }),
    );
    await write(
      "tsconfig.json",
      JSON.stringify({ compilerOptions: { allowImportingTsExtensions: true } }),
    );
    await write("package-lock.json");
    expect(await detectProject(root)).toMatchObject({
      name: undefined,
      packageManager: "npm",
      tsExtensions: true,
    });
  });
});

describe("installCommand", () => {
  it.each([
    ["pnpm", "pnpm add -D a b", "pnpm add a b"],
    ["bun", "bun add -d a b", "bun add a b"],
    ["yarn", "yarn add -D a b", "yarn add a b"],
    ["npm", "npm install -D a b", "npm install a b"],
  ] as const)("%s", (manager, dev, prod) => {
    expect(installCommand(manager, ["a", "b"], true)).toBe(dev);
    expect(installCommand(manager, ["a", "b"])).toBe(prod);
  });

  it("returns the value for a manager it does not know", () => {
    // SAFETY: simulates a manager value outside the union.
    const deno = "deno" as PackageManager;
    expect(installCommand(deno, ["a"])).toBe("deno");
  });
});

describe("publicPrefix", () => {
  const project = (frameworks: Project["frameworks"]): Project => ({
    root: "/",
    name: undefined,
    frameworks,
    packageManager: "pnpm",
    dependencies: {},
    srcDir: ".",
    tsExtensions: false,
    hasSupabase: false,
  });

  it("follows the framework", () => {
    expect(publicPrefix(project(["next", "vite"]))).toBe("NEXT_PUBLIC_");
    expect(publicPrefix(project(["expo"]))).toBe("EXPO_PUBLIC_");
    expect(publicPrefix(project(["vite"]))).toBe("VITE_");
    expect(publicPrefix(project(["hono"]))).toBe("");
  });
});
