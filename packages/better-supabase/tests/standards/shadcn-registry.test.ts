import { readdirSync, readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

import { SPEC_PINS } from "../../src/core/spec-pins.ts";
import { SQL_MODULES } from "../../src/sql/index.ts";
import { problems, validatorFor } from "./validator.ts";

const REGISTRY = new URL("../../../registry/registry.json", import.meta.url);
const PUBLIC = new URL("../../../../apps/marketing/public/r/", import.meta.url);
const VERSION = SPEC_PINS.shadcnRegistry;

const json = (url: URL): Record<string, unknown> =>
  JSON.parse(readFileSync(url, "utf8")) as Record<string, unknown>;

const items = readdirSync(PUBLIC)
  .filter((file) => file.endsWith(".json") && file !== "registry.json")
  .map((file) => [file, json(new URL(file, PUBLIC))] as const);

describe(`shadcn registry (shadcn ${VERSION})`, () => {
  it("vendors the schemas of the pinned release", () => {
    expect(() => validatorFor(`shadcn-registry-${VERSION}.json`)).not.toThrow();
    expect(() =>
      validatorFor(`shadcn-registry-item-${VERSION}.json`),
    ).not.toThrow();
  });

  it("packages/registry/registry.json validates against registry.json", () => {
    const registry = json(REGISTRY);
    expect(registry["$schema"]).toBe(
      "https://ui.shadcn.com/schema/registry.json",
    );
    expect(
      problems(validatorFor(`shadcn-registry-${VERSION}.json`), registry),
    ).toEqual([]);
  });

  it("builds one item file per registry item", () => {
    const names = (json(REGISTRY)["items"] as { name: string }[]).map(
      (item) => `${item.name}.json`,
    );
    expect(items.map(([file]) => file).toSorted()).toEqual(names.toSorted());
  });

  it.each(items)("%s validates against registry-item.json", (_file, item) => {
    expect(item["$schema"]).toBe(
      "https://ui.shadcn.com/schema/registry-item.json",
    );
    expect(
      problems(validatorFor(`shadcn-registry-item-${VERSION}.json`), item),
    ).toEqual([]);
  });

  it.each(items)("%s names catalog blocks in meta.block", (_file, item) => {
    const meta = item["meta"] as { block: string | string[] };
    const blocks = typeof meta.block === "string" ? [meta.block] : meta.block;
    expect(blocks.length).toBeGreaterThan(0);
    expect(blocks.filter((name) => !(name in SQL_MODULES))).toEqual([]);
  });
});
