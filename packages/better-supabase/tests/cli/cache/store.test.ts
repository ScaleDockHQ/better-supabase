import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import {
  cacheEnabled,
  cacheRoot,
  cacheSize,
  listCache,
  purgeCache,
  setCacheEnabled,
} from "../../../src/cli/cache/store.ts";
import { run } from "../../../src/cli/core/run.ts";
import { errorDoc } from "../error-doc.ts";

let root = "";

beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), "bsb-cache-store-"));
  await writeFile(join(root, "package.json"), "{}");
});

afterEach(async () => {
  setCacheEnabled(true);
  await rm(root, { recursive: true, force: true });
});

async function fill(): Promise<void> {
  await mkdir(join(cacheRoot(root), "memo"), { recursive: true });
  await writeFile(join(cacheRoot(root), "memo", "a.json"), "12345");
  await writeFile(join(cacheRoot(root), "render-blocks.json"), "1234567890");
}

describe("the cache folder", () => {
  it("lists and sizes what is cached, and purges all of it", async () => {
    expect(await listCache(root)).toEqual([]);
    expect(await cacheSize(root)).toBe(0);
    expect(await purgeCache(root)).toMatchObject({ removed: [], bytes: 0 });

    await fill();

    expect(await listCache(root)).toEqual(["memo", "render-blocks.json"]);
    expect(await cacheSize(root)).toBe(15);

    expect(await purgeCache(root)).toMatchObject({
      removed: ["memo", "render-blocks.json"],
      bytes: 15,
    });
    expect(await listCache(root)).toEqual([]);
  });

  it("is switched off for one run and back on for the next", async () => {
    await run(["upgrade", "--no-cache", "--cwd", root]);
    expect(cacheEnabled()).toBe(false);

    await run(["cache", "purge", "--cwd", root]);
    expect(cacheEnabled()).toBe(true);
  });
});

describe("cache purge", () => {
  it("removes the entries and reports them", async () => {
    await fill();

    const result = await run(["cache", "purge", "--cwd", root, "--json"]);

    expect(result.code).toBe(0);
    expect(JSON.parse(result.stdout)).toMatchObject({
      status: "success",
      data: {
        cache: { removed: ["memo", "render-blocks.json"], bytes: 15 },
        outcome: "removed",
      },
    });
    expect(await listCache(root)).toEqual([]);
  });

  it("names what a dry run would remove and keeps it", async () => {
    await fill();

    const result = await run(["cache", "purge", "--dry-run", "--cwd", root]);

    expect(result.stdout).toContain("Would remove 2 entries (15 B)");
    expect(await listCache(root)).toEqual(["memo", "render-blocks.json"]);
  });

  it("says so when nothing is cached, with the command that fills it", async () => {
    const result = await run(["cache", "purge", "--cwd", root, "--json"]);

    expect(JSON.parse(result.stdout)).toMatchObject({
      data: { outcome: "unchanged" },
      next: [{ command: "better-supabase gen" }],
    });
  });

  it("rejects an unknown option with exit code 2", async () => {
    const result = await run([
      "cache",
      "purge",
      "--all",
      "--cwd",
      root,
      "--json",
    ]);

    expect(result.code).toBe(2);
    expect(errorDoc(result)).toMatchObject({ reason: "unknown_flag" });
  });
});
