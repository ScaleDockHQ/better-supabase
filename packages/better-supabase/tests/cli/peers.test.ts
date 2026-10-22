import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import {
  declaredPeers,
  installedVersion,
  peerVersions,
  satisfies,
  versionAt,
} from "../../src/cli/peers.ts";

describe("satisfies", () => {
  it.each([
    ["0.4.0", "0.4.0", true],
    ["0.4.1", "0.4.0", false],
    ["0.4.1", ">=0.4.0 <0.5", true],
    ["0.5.0", ">=0.4.0 <0.5", false],
    ["2.2.0", ">=2.3.0 <3", false],
    ["2.3.1", ">=2.3.0 <3", true],
    ["3.0.0", ">=2.3.0 <3", false],
    ["19.2.0", "^19", true],
    ["20.0.0", "^19", false],
    ["5.61.9", "^5.62.0", false],
    ["0.4.9", "^0.4.0", true],
    ["0.5.0", "^0.4.0", false],
    ["16.3.0", ">=16.3 <17", true],
    ["1.0.0", ">=1", true],
    ["2.0.0-beta.42", ">=2.0.0-beta.40 <3", true],
    ["2.0.0-beta.39", ">=2.0.0-beta.40 <3", false],
    ["2.0.0", ">=2.0.0-beta.40 <3", true],
    ["3.0.0-rc.1", ">=2 <3", false],
    ["2.1.0", ">= 2 < 3", true],
    ["4.0.0", "^2 || ^4", true],
    ["5.0.2+build.1", ">=5.0.2 <5.1", true],
  ])("%s in %s is %s", (version, range, expected) => {
    expect(satisfies(version, range)).toBe(expected);
  });

  it("returns undefined for what it can't parse", () => {
    expect(satisfies("latest", ">=1")).toBeUndefined();
    expect(satisfies("1.0.0", "~1.0")).toBeUndefined();
    expect(satisfies("1.0.0", "workspace:*")).toBeUndefined();
  });
});

describe("installed versions", () => {
  it("finds a package in node_modules above the root", async () => {
    const root = await mkdtemp(join(tmpdir(), "bsb-peers-"));
    const pkg = join(root, "node_modules", "@scope", "lib");
    await mkdir(pkg, { recursive: true });
    await writeFile(
      join(pkg, "package.json"),
      JSON.stringify({ name: "@scope/lib", version: "1.2.3" }),
    );
    const app = join(root, "apps", "web");
    await mkdir(app, { recursive: true });
    expect(await installedVersion("@scope/lib", app)).toBe("1.2.3");
    expect(await installedVersion("missing", app)).toBeUndefined();

    await mkdir(join(pkg, "dist"), { recursive: true });
    expect(await versionAt(join(pkg, "dist", "index.js"))).toBe("1.2.3");
  });

  it("reads the declared peers and their installed versions", async () => {
    // The workspace manifest says `catalog:peers`; the published one has the ranges.
    const peers = await declaredPeers();
    expect(peers).toHaveProperty("@supabase/supabase-js");
    const versions = await peerVersions(import.meta.dirname);

    const supabase = versions.find(
      (peer) => peer.name === "@supabase/supabase-js",
    );

    expect(supabase?.installed).toMatch(/^2\./);
  });
});
