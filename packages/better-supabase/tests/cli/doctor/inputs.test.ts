import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import {
  functionFiles,
  readGitignores,
  seedFiles,
  sourceGlobs,
} from "../../../src/cli/doctor/inputs.ts";
import { CONFIG_DEFAULTS, resolveConfig } from "../../../src/config/index.ts";

describe("sourceGlobs", () => {
  let root: string;

  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "bsb-doctor-sources-"));
  });

  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
  });

  const writePackage = async (dir: string, name: string) => {
    await mkdir(join(root, dir), { recursive: true });
    await writeFile(join(root, dir, "package.json"), JSON.stringify({ name }));
  };

  it("keeps the default outside a workspace", async () => {
    await writePackage(".", "app");

    expect(await sourceGlobs(resolveConfig({}, root))).toEqual(
      CONFIG_DEFAULTS.doctor.sources,
    );
  });

  it("adds each workspace package to the default", async () => {
    await writeFile(
      join(root, "pnpm-workspace.yaml"),
      "packages:\n  - apps/*\n",
    );
    await writePackage(".", "root");
    await writePackage("apps/web", "web");

    const globs = await sourceGlobs(resolveConfig({}, root));

    expect(globs).toEqual(
      expect.arrayContaining([
        ...CONFIG_DEFAULTS.doctor.sources,
        ...CONFIG_DEFAULTS.doctor.sources.map((glob) => `apps/web/${glob}`),
      ]),
    );
  });

  it("uses configured sources as they are", async () => {
    await writeFile(
      join(root, "pnpm-workspace.yaml"),
      "packages:\n  - apps/*\n",
    );
    await writePackage("apps/web", "web");

    expect(
      await sourceGlobs(
        resolveConfig(
          { tooling: { doctor: { sources: ["lib/**/*.ts"] } } },
          root,
        ),
      ),
    ).toEqual(["lib/**/*.ts"]);
  });
});

describe("seedFiles", () => {
  let root: string;

  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "bsb-doctor-seeds-"));
  });

  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
  });

  it("reads the .sql files of the seeds folder, sorted, and nothing else", async () => {
    expect(await seedFiles(root, undefined)).toEqual([]);

    await mkdir(join(root, "supabase/seeds"), { recursive: true });
    await writeFile(join(root, "supabase/seeds/b.sql"), "select 2;\n");
    await writeFile(join(root, "supabase/seeds/a.sql"), "select 1;\n");
    await writeFile(join(root, "supabase/seeds/notes.md"), "skip\n");

    expect(await seedFiles(root, undefined)).toEqual([
      { path: "supabase/seeds/a.sql", text: "select 1;\n" },
      { path: "supabase/seeds/b.sql", text: "select 2;\n" },
    ]);
  });
});

describe("functionFiles", () => {
  let root: string;

  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "bsb-doctor-functions-"));
  });

  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
  });

  it("returns nothing without a functions folder", async () => {
    expect(await functionFiles(root, undefined)).toEqual([]);
  });

  it("reads script files in path order and skips node_modules and other files", async () => {
    const dir = join(root, "supabase", "functions");

    await mkdir(join(dir, "hello"), { recursive: true });
    await mkdir(join(dir, "hello", "node_modules", "dep"), { recursive: true });
    await writeFile(join(dir, "hello", "index.ts"), "export {};");
    await writeFile(join(dir, "a.mjs"), "export {};");
    await writeFile(join(dir, "notes.md"), "# notes");
    await writeFile(
      join(dir, "hello", "node_modules", "dep", "index.js"),
      "module.exports = {};",
    );

    expect(await functionFiles(root, undefined)).toEqual([
      { path: "supabase/functions/a.mjs", text: "export {};" },
      { path: "supabase/functions/hello/index.ts", text: "export {};" },
    ]);
  });
});

describe("readGitignores", () => {
  let root: string;

  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "bsb-doctor-gitignore-"));
  });

  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
  });

  it("joins the app's rules with each parent's up to the repository root", async () => {
    await mkdir(join(root, ".git"), { recursive: true });
    await mkdir(join(root, "apps/web"), { recursive: true });
    await writeFile(join(root, ".gitignore"), ".env*\n");
    await writeFile(join(root, "apps/web/.gitignore"), ".next\n");

    const text = await readGitignores(join(root, "apps/web"));

    expect(text.split("\n").filter(Boolean)).toEqual([".next", ".env*"]);
  });

  it("stops at the repository root", async () => {
    await mkdir(join(root, "repo/.git"), { recursive: true });
    await writeFile(join(root, ".gitignore"), "outside\n");
    await writeFile(join(root, "repo/.gitignore"), "inside\n");

    expect(await readGitignores(join(root, "repo"))).toBe("inside\n");
  });
});
