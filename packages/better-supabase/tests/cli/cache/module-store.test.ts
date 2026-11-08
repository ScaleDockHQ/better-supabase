import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { installMemo } from "../../../src/cli/cache/memo-backend.ts";
import { createDiskModuleStore } from "../../../src/cli/cache/module-store.ts";
import { setCacheEnabled } from "../../../src/cli/cache/store.ts";
import {
  moduleRenderStats,
  renderBlocks,
  setModuleRenderStore,
  setParseStore,
  SQL_MODULES,
} from "../../../src/sql/index.ts";

let folder = "";

beforeEach(async () => {
  folder = await mkdtemp(join(tmpdir(), "bsb-module-store-"));
  setCacheEnabled(true);
});

afterEach(async () => {
  setModuleRenderStore(undefined);
  setParseStore(undefined);
  await rm(folder, { recursive: true, force: true });
});

const names = ["organizations", "tasks", "audit"];

describe("the disk module store", () => {
  it("serves a later process the modules an earlier one rendered", () => {
    const first = createDiskModuleStore(folder, "s1");
    setModuleRenderStore(first);
    const fresh = renderBlocks(names, {});
    expect(first.flush()).toBe(true);

    const second = createDiskModuleStore(folder, "s1");
    setModuleRenderStore(second);
    const before = moduleRenderStats.hits;
    const cached = renderBlocks(names, {});

    expect(cached).toEqual(fresh);
    expect(moduleRenderStats.hits - before).toBeGreaterThanOrEqual(
      names.length,
    );
    expect(second.flush()).toBe(false);
  });

  it("drops entries of another release and a file that can't be read", async () => {
    const first = createDiskModuleStore(folder, "s1");
    setModuleRenderStore(first);
    renderBlocks(["tasks"], {});
    first.flush();

    setModuleRenderStore(createDiskModuleStore(folder, "s2"));
    const before = moduleRenderStats.hits;
    renderBlocks(["tasks"], {});
    expect(moduleRenderStats.hits - before).toBe(0);

    await writeFile(join(folder, "modules", "renders.json"), "{ nope");
    setModuleRenderStore(createDiskModuleStore(folder, "s1"));
    const damaged = moduleRenderStats.hits;
    expect(renderBlocks(["tasks"], {}).length).toBeGreaterThan(0);
    expect(moduleRenderStats.hits - damaged).toBe(0);
  });

  it("is installed by the CLI unless the run has no cache", async () => {
    await installMemo(folder);
    renderBlocks(["tasks"], {});
    const before = moduleRenderStats.hits;
    renderBlocks(["tasks"], {});
    expect(moduleRenderStats.hits).toBeGreaterThan(before);

    setCacheEnabled(false);
    await installMemo(folder);
    const off = { ...moduleRenderStats };
    renderBlocks(["tasks"], {});
    expect(moduleRenderStats).toEqual(off);
    setCacheEnabled(true);
  });

  it("renders every registered module from a store a full render filled", () => {
    const store = createDiskModuleStore(folder, "s1");
    setModuleRenderStore(store);
    const all = Object.keys(SQL_MODULES);
    renderBlocks(all, {});

    const before = moduleRenderStats.misses;
    renderBlocks(all, {});
    expect(moduleRenderStats.misses).toBe(before);
  });
});
