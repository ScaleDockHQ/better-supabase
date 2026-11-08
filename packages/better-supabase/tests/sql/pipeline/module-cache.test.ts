import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type { BlockSqlFile, BlockSqlLayout } from "../../../src/sql/index.ts";

import {
  moduleRenderStats,
  renderBlocks,
  setModuleRenderStore,
  SQL_MODULES,
} from "../../../src/sql/index.ts";
import { renderModuleCached } from "../../../src/sql/pipeline/module-cache.ts";

const names = Object.keys(SQL_MODULES);
let held = new Map<string, unknown>();

const install = (salt = "test"): void => {
  setModuleRenderStore({
    salt,
    get: (key) => held.get(key),
    set: (key, entry) => void held.set(key, entry),
  });
};

const counts = (): { hits: number; misses: number; uncacheable: number } => ({
  ...moduleRenderStats,
});

/** The module renders a call served and made, as the change from before it. */
function measured(run: () => void): { hits: number; misses: number } {
  const before = counts();
  run();
  const after = counts();

  return {
    hits: after.hits - before.hits,
    misses: after.misses - before.misses,
  };
}

const plain = (layout: BlockSqlLayout): BlockSqlFile[] => {
  setModuleRenderStore(undefined);
  const files = renderBlocks(names, layout);
  install();

  return files;
};

beforeEach(() => {
  held = new Map();
  install();
});

afterEach(() => {
  setModuleRenderStore(undefined);
});

// Each case renders every module more than once; a busy machine needs the room.
describe(
  "renderBlocks with a module render store",
  { timeout: 120_000 },
  () => {
    it("renders the same bytes as without it, on a miss and on a hit", () => {
      const fresh = plain({});
      const first = renderBlocks(names, {});
      const second = renderBlocks(names, {});

      expect(first).toEqual(fresh);
      expect(second).toEqual(fresh);
    });

    it("serves every module from the store on a second render", () => {
      renderBlocks(names, {});
      const again = measured(() => void renderBlocks(names, {}));

      expect(again.misses).toBe(0);
      expect(again.hits).toBeGreaterThan(100);
    });

    it("renders again only the module that read a changed input", () => {
      renderBlocks(names, {});

      const changed = measured(
        () => void renderBlocks(names, { realtimeTables: ["public.live"] }),
      );

      expect(changed.misses).toBe(1);
      expect(changed.hits).toBeGreaterThan(100);

      const files = renderBlocks(names, { realtimeTables: ["public.live"] });
      expect(files).toEqual(plain({ realtimeTables: ["public.live"] }));
      expect(
        files.find((file) => file.module === "realtime-tables")?.contents,
      ).toContain("public.live");
    });

    it("renders again only the audit module when the audited tables change", () => {
      renderBlocks(names, {});

      const audited = {
        auditedTables: [{ target: "public.notes", ignore: [], redact: [] }],
      };

      const changed = measured(() => void renderBlocks(names, audited));

      expect(changed.misses).toBeLessThanOrEqual(3);
      expect(changed.misses).toBeGreaterThanOrEqual(1);
      expect(renderBlocks(names, audited)).toEqual(plain(audited));
    });

    it("leaves every entry valid when the change is an input no module reads", () => {
      renderBlocks(names, {});

      const unread = measured(
        () =>
          void renderBlocks(names, {
            somethingNoModuleReads: "x",
          } as BlockSqlLayout),
      );

      expect(unread.misses).toBe(0);
    });

    it("renders everything again when an input every module reads changes", () => {
      renderBlocks(names, {});

      const changed = measured(
        () => void renderBlocks(names, { dir: "other" }),
      );

      expect(changed.hits).toBe(0);
      expect(changed.misses).toBeGreaterThan(100);
      expect(renderBlocks(names, { dir: "other" })).toEqual(
        plain({ dir: "other" }),
      );
    });

    it("matches a fresh render after any sequence of app-side edits", () => {
      const table = (name: string): [string, string] => [
        `public.${name}`,
        `supabase/schemas/${name}.sql`,
      ];

      const layouts: BlockSqlLayout[] = [
        {},
        { ownTables: Object.fromEntries([table("widgets")]) },
        { ownTables: Object.fromEntries([table("widgets"), table("gadgets")]) },
        {
          ownTables: Object.fromEntries([table("widgets"), table("gadgets")]),
          declaredTables: ["public.widgets", "public.gadgets"],
        },
        {
          realtimeTables: ["public.widgets"],
          realtimeGlobal: ["public.gadgets"],
        },
        { customAccessTokenHook: "public.hook", rerunnable: true },
        { rerunnable: true },
        {},
      ];

      const few = [
        "organizations",
        "tasks",
        "audit",
        "realtime-tables",
        "grants",
      ];

      for (const layout of layouts) {
        const fresh = (): BlockSqlFile[] => {
          setModuleRenderStore(undefined);
          const files = renderBlocks(few, layout);
          install();

          return files;
        };

        expect(renderBlocks(few, layout)).toEqual(fresh());
      }
    });

    it("serves the earlier entry again when the input changes back", () => {
      const base = renderBlocks(names, {});
      renderBlocks(names, { realtimeTables: ["public.live"] });
      const back = measured(() => void renderBlocks(names, {}));

      // The realtime module's entry now holds the second render, so it renders once more.
      expect(back.misses).toBe(1);
      expect(renderBlocks(names, {})).toEqual(base);
    });

    it("never serves an entry from another generator", () => {
      renderBlocks(["tasks"], {});
      install("other-generator");
      const again = measured(() => void renderBlocks(["tasks"], {}));

      expect(again.hits).toBe(0);
    });
  },
);

describe("renderModuleCached", () => {
  const file = (contents: string): BlockSqlFile => ({
    module: "demo",
    kind: "schema",
    path: "demo.sql",
    contents,
  });

  it("stores nothing for a render that throws", () => {
    expect(() =>
      renderModuleCached("demo", {}, [], () => {
        throw new Error("refused");
      }),
    ).toThrow("refused");
    expect(held.size).toBe(0);
  });

  it("renders the real input when only the proxy made the render throw", () => {
    const layout = { rerunnable: true } as BlockSqlLayout;
    let calls = 0;

    const files = renderModuleCached("clone", layout, [], (given) => {
      calls += 1;
      structuredClone(given);

      return [file("cloned")];
    });

    expect(files[0]?.contents).toBe("cloned");
    expect(calls).toBe(2);
    expect(held.size).toBe(0);
  });

  it("does not store a render that called a function from the layout", () => {
    const layout: BlockSqlLayout = { rerunnable: true };
    const before = counts();

    const files = renderModuleCached("demo", layout, [], (tracked) => [
      file(String(tracked.customAccessTokenHook)),
    ]);

    expect(files[0]?.contents).toBe("undefined");

    const fnLayout = {
      accessProvider: { functions: { rowsWith: () => "x" } },
    } as unknown as BlockSqlLayout;

    renderModuleCached("fn", fnLayout, [], (tracked) => {
      const provider = tracked.accessProvider as unknown as {
        functions: { rowsWith: () => string };
      };

      return [file(provider.functions.rowsWith())];
    });

    expect(counts().uncacheable - before.uncacheable).toBe(1);
    expect([...held.keys()].some((key) => key.includes("fn"))).toBe(false);
  });

  it("runs the render as it is without a store", () => {
    setModuleRenderStore(undefined);
    const layout = { dir: "d" };

    const files = renderModuleCached("demo", layout, [], (given) => {
      expect(given).toBe(layout);

      return [file("x")];
    });

    expect(files).toHaveLength(1);
    expect(held.size).toBe(0);
  });

  it("ignores a stored entry of the wrong shape", () => {
    held.set("test:demo", { reads: "no", files: [] });
    const files = renderModuleCached("demo", {}, [], () => [file("fresh")]);

    expect(files[0]?.contents).toBe("fresh");
  });
});
