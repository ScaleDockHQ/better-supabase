import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import {
  cacheOf,
  clearRenderMemory,
  renderBlocksCached,
  renderStats,
} from "../../../src/cli/sql/render-cache.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { renderBlocks } from "../../../src/sql/index.ts";

let root = "";

beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), "bsb-render-cache-"));
  clearRenderMemory();
  renderStats.fresh = 0;
  renderStats.memory = 0;
  renderStats.disk = 0;
});

afterEach(async () => {
  await rm(root, { recursive: true, force: true });
});

const NAMES = ["organizations", "memberships"];

const file = (): string =>
  join(root, "node_modules/.cache/better-supabase/render-blocks.json");

describe("renderBlocksCached", () => {
  it("returns the fresh output byte for byte, from memory and from disk", async () => {
    const config = resolveConfig({ blocks: {} }, root);
    const fresh = renderBlocks(NAMES, {});

    expect(await renderBlocksCached(config, NAMES, {})).toStrictEqual(fresh);
    expect(renderStats).toMatchObject({ fresh: 1, memory: 0, disk: 0 });

    expect(await renderBlocksCached(config, NAMES, {})).toStrictEqual(fresh);
    expect(renderStats.memory).toBe(1);

    clearRenderMemory();
    expect(await renderBlocksCached(config, NAMES, {})).toStrictEqual(fresh);
    expect(renderStats).toMatchObject({ fresh: 1, memory: 1, disk: 1 });
  });

  it("renders again when the input changes", async () => {
    const config = resolveConfig({ blocks: {} }, root);
    await renderBlocksCached(config, NAMES, {});
    await renderBlocksCached(config, ["organizations"], {});

    expect(renderStats.fresh).toBe(2);
  });

  it("drops a disk entry whose file no longer matches its hash", async () => {
    const config = resolveConfig({ blocks: {} }, root);
    await renderBlocksCached(config, NAMES, {});
    const text = await readFile(file(), "utf-8");
    await writeFile(file(), text.replace("create table", "create  table"));
    clearRenderMemory();
    const again = await renderBlocksCached(config, NAMES, {});

    expect(again).toStrictEqual(renderBlocks(NAMES, {}));
    expect(renderStats.disk).toBe(0);
    expect(renderStats.fresh).toBe(2);
  });

  it("ignores an unreadable disk entry", async () => {
    const config = resolveConfig({ blocks: {} }, root);
    await renderBlocksCached(config, NAMES, {});
    await writeFile(file(), "not json");
    clearRenderMemory();
    await renderBlocksCached(config, NAMES, {});

    expect(renderStats.fresh).toBe(2);
    await writeFile(file(), JSON.stringify({ key: 1 }));
    clearRenderMemory();
    await renderBlocksCached(config, NAMES, {});

    expect(renderStats.fresh).toBe(3);
  });

  it("renders fresh and writes nothing with cache: false", async () => {
    const config = resolveConfig({ blocks: {} }, root);
    await renderBlocksCached(config, NAMES, {}, { cache: false });
    await renderBlocksCached(config, NAMES, {}, cacheOf({ "no-cache": true }));

    expect(renderStats.fresh).toBe(2);
    await expect(readFile(file(), "utf-8")).rejects.toThrow(/ENOENT/);
    expect(cacheOf({})).toStrictEqual({ cache: true });
  });
});
