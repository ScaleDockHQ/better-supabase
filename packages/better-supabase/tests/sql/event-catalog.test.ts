import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

import { BLOCK_EVENT_RENAMES } from "../../src/core/block-events.ts";
import { renderModules, SQL_MODULES } from "../../src/sql/registry.ts";

const source = (path: string): string =>
  readFileSync(new URL(path, import.meta.url), "utf8");

/** The keys of `BlockEventMap`, read from its source. */
const MAP_TYPES = (() => {
  const map = /export interface BlockEventMap \{([\s\S]*?)\n\}/.exec(
    source("../../src/core/block-events.ts"),
  )?.[1];
  return [...(map ?? "").matchAll(/^\s+"([a-z_.]+)":/gm)].map(
    (match) => match[1] ?? "",
  );
})();

/** Rendered with every module, so each optional event path is on. */
const RECORDED = (() => {
  const files = renderModules(Object.keys(SQL_MODULES), {
    modules: { audit: { options: { restricted: true } } },
  });
  const byModule = new Map<string, Set<string>>();
  for (const file of files) {
    for (const match of file.contents.matchAll(/emit_event\('([a-z_.]+)'/g)) {
      const types = byModule.get(file.module) ?? new Set<string>();
      types.add(match[1] ?? "");
      byModule.set(file.module, types);
    }
  }
  return byModule;
})();

/** Events only a module option turns on. */
const OPTIONAL = new Set(["object.uploaded"]);

const declared = (module: string): string[] =>
  Object.keys(SQL_MODULES[module]?.names?.events ?? {});

describe("SQL module event catalog", () => {
  it("declares the events of every module that records one", () => {
    expect(RECORDED.size).toBeGreaterThan(20);
    const mismatches = [...RECORDED].flatMap(([module, types]) => {
      const catalog = declared(module);
      if (catalog.length === 0) return [`${module}: no catalog`];
      return catalog
        .filter((type) => !types.has(type) && !OPTIONAL.has(type))
        .map((type) => `${module}: ${type} is never recorded`);
    });
    expect(mismatches).toEqual([]);
  });

  it("declares only types in BlockEventMap", () => {
    const known = new Set(MAP_TYPES);
    const unknown = Object.keys(SQL_MODULES).flatMap((module) =>
      declared(module)
        .filter((type) => !known.has(type))
        .map((type) => `${module}: ${type}`),
    );
    expect(unknown).toEqual([]);
  });

  it("names events <entity>.<past_verb>, spelled one way", () => {
    const typeName = /^[a-z]+(_[a-z]+)*\.[a-z]+(_[a-z]+)*$/;
    const past = /(ed|left|set|sent)$/;
    expect(
      MAP_TYPES.filter(
        (type) =>
          !typeName.test(type) || !past.test(type) || type.includes("canceled"),
      ),
    ).toEqual([]);
  });

  it("maps every renamed type to a current one", () => {
    const known = new Set(MAP_TYPES);
    expect(
      Object.entries(BLOCK_EVENT_RENAMES).filter(
        ([from, to]) => known.has(from) || !known.has(to),
      ),
    ).toEqual([]);
  });

  it("lists every type on the events docs page", () => {
    const docs = source(
      "../../../../apps/docs/content/docs/extending/events.mdx",
    );
    expect(MAP_TYPES.filter((type) => !docs.includes(`\`${type}\``))).toEqual(
      [],
    );
  });
});
