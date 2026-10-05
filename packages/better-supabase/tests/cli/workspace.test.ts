import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import {
  detectWorkspace,
  pnpmWorkspacePatterns,
  suggestedPackage,
} from "../../src/cli/workspace.ts";

let root: string;

beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), "better-supabase-workspace-"));
});

afterEach(async () => {
  await rm(root, { recursive: true, force: true });
});

async function write(files: Record<string, string>): Promise<void> {
  for (const [path, contents] of Object.entries(files)) {
    await mkdir(dirname(join(root, path)), { recursive: true });
    await writeFile(join(root, path), contents);
  }
}

const pkg = (name: string, dependencies: Record<string, string> = {}) =>
  JSON.stringify({ name, dependencies });

describe("pnpmWorkspacePatterns", () => {
  it("reads block lists with quotes and comments", () => {
    expect(
      pnpmWorkspacePatterns(
        [
          "# workspace",
          "packages:",
          '  - "apps/*"',
          "  # tooling",
          "  - 'packages/*' # libraries",
          "  - '!packages/legacy'",
          "",
          "catalog:",
          "  react: 19.0.0",
        ].join("\n"),
      ),
    ).toEqual(["apps/*", "packages/*", "!packages/legacy"]);
  });

  it("reads flow lists and files without packages", () => {
    expect(pnpmWorkspacePatterns('packages: ["apps/*", tools/cli]\n')).toEqual([
      "apps/*",
      "tools/cli",
    ]);
    expect(pnpmWorkspacePatterns("catalog:\n  a: 1\n")).toEqual([]);
  });
});

describe("detectWorkspace", () => {
  it("lists the packages of pnpm-workspace.yaml in path order", async () => {
    await write({
      "package.json": pkg("root"),
      "pnpm-workspace.yaml":
        "packages:\n  - apps/*\n  - packages/*\n  - '!packages/legacy'\n",
      "apps/web/package.json": pkg("@acme/web", { next: "16" }),
      "packages/runtime/package.json": pkg("@acme/runtime", {
        "better-supabase": "0.5.1",
      }),
      "packages/legacy/package.json": pkg("@acme/legacy"),
      "packages/runtime/node_modules/dep/package.json": pkg("dep"),
    });
    const workspace = await detectWorkspace(root);
    expect(workspace?.file).toBe("pnpm-workspace.yaml");
    expect(
      workspace?.packages.map((entry) => [entry.dir, entry.project.name]),
    ).toEqual([
      ["apps/web", "@acme/web"],
      ["packages/runtime", "@acme/runtime"],
    ]);
    expect(suggestedPackage(workspace!)).toBe("packages/runtime");
  });

  it("reads package.json workspaces as a list or an object", async () => {
    await write({
      "package.json": JSON.stringify({ workspaces: ["apps/*"] }),
      "apps/web/package.json": pkg("web", { hono: "4" }),
      "apps/docs/package.json": pkg("docs"),
    });
    const listed = await detectWorkspace(root);
    expect(listed?.file).toBe("package.json");
    expect(suggestedPackage(listed!)).toBe("apps/web");

    await write({
      "package.json": JSON.stringify({
        workspaces: { packages: ["apps/docs"] },
      }),
    });
    const object = await detectWorkspace(root);
    expect(object?.packages.map((entry) => entry.dir)).toEqual(["apps/docs"]);
    expect(suggestedPackage(object!)).toBe("apps/docs");
  });

  it("returns undefined outside a workspace root", async () => {
    expect(await detectWorkspace(root)).toBeUndefined();
    await write({ "package.json": "{" });
    expect(await detectWorkspace(root)).toBeUndefined();
    await write({ "package.json": pkg("app") });
    expect(await detectWorkspace(root)).toBeUndefined();
    await write({ "package.json": JSON.stringify({ workspaces: "apps/*" }) });
    expect(await detectWorkspace(root)).toBeUndefined();
    await write({ "package.json": "null" });
    expect(await detectWorkspace(root)).toBeUndefined();
  });

  it("suggests nothing for a workspace without packages", async () => {
    await write({ "pnpm-workspace.yaml": "packages:\n  - apps/*\n" });
    const workspace = await detectWorkspace(root);
    expect(workspace?.packages).toEqual([]);
    expect(suggestedPackage(workspace!)).toBeUndefined();
  });
});
