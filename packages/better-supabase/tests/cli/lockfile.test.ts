import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { lockedPackage, lockedVersions } from "../../src/cli/lockfile.ts";

const PNPM = `lockfileVersion: '9.0'

importers:

  .:
    dependencies:
      better-supabase:
        specifier: ^0.35.0
        version: 0.35.0(@supabase/supabase-js@2.118.0)

packages:

  better-supabase@0.35.0:
    resolution: {integrity: sha512-x}

  better-supabase-extra@1.0.0:
    resolution: {integrity: sha512-y}

snapshots:

  better-supabase@0.35.0(@supabase/supabase-js@2.118.0):
    dependencies:
      '@supabase/supabase-js': 2.118.0
`;

const PACKAGE_LOCK = JSON.stringify({
  lockfileVersion: 3,
  packages: {
    "": { dependencies: { "better-supabase": "^0.35.0" } },
    "node_modules/better-supabase": { version: "0.35.1" },
    "apps/web/node_modules/better-supabase": { version: "0.34.0" },
    "node_modules/other": { version: "1.0.0" },
  },
});

const YARN = `__metadata:
  version: 8

"better-supabase@npm:^0.35.0":
  version: 0.35.2
  resolution: "better-supabase@npm:0.35.2"

"better-supabase@workspace:packages/better-supabase":
  version: 0.0.0-use.local
`;

const YARN_CLASSIC = `better-supabase@^0.35.0:
  version "0.35.3"
  resolved "https://registry.yarnpkg.com/better-supabase/-/better-supabase-0.35.3.tgz"
`;

const BUN = `{
  "lockfileVersion": 1,
  "packages": {
    "better-supabase": ["better-supabase@0.35.4", "", {}, "sha512-z"],
    "linked": ["better-supabase@workspace:packages/better-supabase"],
  }
}`;

describe("lockedVersions", () => {
  it("reads each lockfile format", () => {
    expect(lockedVersions("pnpm-lock.yaml", "better-supabase", PNPM)).toEqual([
      "0.35.0",
    ]);
    expect(
      lockedVersions("package-lock.json", "better-supabase", PACKAGE_LOCK),
    ).toEqual(["0.35.1", "0.34.0"]);
    expect(lockedVersions("yarn.lock", "better-supabase", YARN)).toEqual([
      "0.35.2",
    ]);
    expect(
      lockedVersions("yarn.lock", "better-supabase", YARN_CLASSIC),
    ).toEqual(["0.35.3"]);
    expect(lockedVersions("bun.lock", "better-supabase", BUN)).toEqual([
      "0.35.4",
    ]);
  });

  it("leaves out workspace links", () => {
    const linked = PNPM.replace(/packages:[\s\S]*/, "").replace(
      "0.35.0(@supabase/supabase-js@2.118.0)",
      "link:../../packages/x",
    );

    expect(lockedVersions("pnpm-lock.yaml", "better-supabase", linked)).toEqual(
      [],
    );
    expect(lockedVersions("package-lock.json", "better-supabase", "{")).toEqual(
      [],
    );
  });
});

describe("lockedPackage", () => {
  let root: string;

  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "better-supabase-lockfile-"));
  });

  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
  });

  it("finds the nearest lockfile above the project", async () => {
    const app = join(root, "apps", "web");
    await mkdir(app, { recursive: true });
    await writeFile(join(root, "pnpm-lock.yaml"), PNPM);

    expect(await lockedPackage("better-supabase", app)).toEqual({
      path: join("..", "..", "pnpm-lock.yaml"),
      install: "pnpm install",
      versions: ["0.35.0"],
    });
  });
});
