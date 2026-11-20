import { readFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { describe, expect, it } from "vitest";

import { WORKFLOW_WORLD_PROTOCOL } from "../../../src/workflow-sdk/world/types.ts";

const root = join(import.meta.dirname, "../../..");

interface Manifest {
  files?: string[];
  exports?: Record<string, unknown>;
  publishConfig?: { exports?: Record<string, unknown> };
  peerDependencies?: Record<string, string>;
}

async function manifest(path: string): Promise<Manifest> {
  // SAFETY: the files read here are this package's own JSON manifests.
  return JSON.parse(await readFile(join(root, path), "utf-8")) as Manifest;
}

/**
 * Eve reads `<world>/package.json` and compares the major of the declared
 * `@workflow/core` or `@workflow/world` range with the line it bundles (eve's
 * `world-compatibility.js`); this repeats that comparison.
 */
function major(range: string): number {
  const match = /(\d+)\.(?:\d+|x|\*)/u.exec(range.trim());

  if (match === null) {
    throw new TypeError(`no version in ${range}`);
  }

  return Number(match[1]);
}

async function declaredRange(): Promise<string> {
  const range = (await manifest("api/workflow-sdk-world.json"))
    .peerDependencies?.["@workflow/world"];

  if (range === undefined) {
    throw new TypeError("the manifest declares no @workflow/world range");
  }

  return range;
}

describe("the workflow-sdk/world manifest", () => {
  it("is exported so eve's startup check can resolve it", async () => {
    const pkg = await manifest("package.json");
    const key = "./workflow-sdk/world/package.json";

    expect(pkg.exports?.[key]).toBe("./api/workflow-sdk-world.json");
    expect(pkg.publishConfig?.exports?.[key]).toBe(
      "./api/workflow-sdk-world.json",
    );
    expect(pkg.files).toContain("api/workflow-sdk-world.json");
  });

  it("declares the @workflow/world line the World speaks", async () => {
    const range = await declaredRange();

    expect(major(range)).toBe(major(WORKFLOW_WORLD_PROTOCOL));
    expect(range).toContain(WORKFLOW_WORLD_PROTOCOL);
  });

  it("matches the @workflow/world installed with eve", async () => {
    // The package doesn't export its manifest, so read the file its entry sits in.
    const entry = createRequire(import.meta.url).resolve("@workflow/world");

    const installed = JSON.parse(
      await readFile(join(dirname(entry), "..", "package.json"), "utf-8"),
    ) as { version: string };

    expect(installed.version).toBe(WORKFLOW_WORLD_PROTOCOL);
    expect(major(await declaredRange())).toBe(major(installed.version));
  });

  it("keeps the peer range equal to the catalog's", async () => {
    const workspace = await readFile(
      join(root, "../../pnpm-workspace.yaml"),
      "utf-8",
    );

    expect(workspace).toContain(
      `"@workflow/world": "${await declaredRange()}"`,
    );
  });
});
