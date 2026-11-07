import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import type * as Peers from "../../../src/cli/peers.ts";

import { generatedLibraryNotices } from "../../../src/cli/gen/notices.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { valibot } from "../../../src/generators/valibot/index.ts";
import { zod } from "../../../src/generators/zod/index.ts";

// In the source tree the peers are `catalog:peers`; the published manifest has
// the ranges, which this stands in for.
vi.mock("../../../src/cli/peers.ts", async (importOriginal) => ({
  ...(await importOriginal<typeof Peers>()),
  declaredPeers: () =>
    Promise.resolve({ zod: ">=4 <5", valibot: ">=1 <2", nuqs: ">=2.3 <3" }),
}));

let root = "";

beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), "bsb-generated-library-"));
});

afterEach(async () => {
  await rm(root, { recursive: true, force: true });
});

async function install(name: string, version: string): Promise<void> {
  await mkdir(join(root, "node_modules", name), { recursive: true });

  await writeFile(
    join(root, "node_modules", name, "package.json"),
    JSON.stringify({ name, version }),
  );
}

describe("generatedLibraryNotices", () => {
  it("names a generator whose library is outside the tested range", async () => {
    await install("zod", "3.25.0");
    await install("valibot", "1.5.0");

    const config = resolveConfig({ gen: { generators: [zod(), valibot()] } }, root);

    const [notice, ...rest] = await generatedLibraryNotices(config);

    expect(rest).toEqual([]);
    expect(notice).toContain("the zod() generator writes code for zod >=4 <5");
    expect(notice).toContain("zod 3.25.0 is installed");
  });

  it("says nothing for a library in range, a missing one, or no generator", async () => {
    await install("zod", "4.6.7");

    expect(
      await generatedLibraryNotices(
        resolveConfig({ gen: { generators: [zod(), valibot()] } }, root),
      ),
    ).toEqual([]);
    expect(await generatedLibraryNotices(resolveConfig({}, root))).toEqual([]);
  });
});
