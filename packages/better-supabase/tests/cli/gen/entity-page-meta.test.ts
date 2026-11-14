import { describe, expect, it } from "vitest";

import {
  entityPageMessageKeys,
  entityPageSeedRows,
  seedValue,
} from "../../../src/cli/gen/entity-page-meta.ts";
import {
  emitEntityPages,
  ENTITY_PAGE_OUTPUTS,
  resolveEntityPage,
} from "../../../src/cli/gen/entity-pages.ts";
import { resolveConfig } from "../../../src/config/resolve.ts";
import { defineEntityPage } from "../../../src/list/entity-page.ts";

const risks = defineEntityPage({
  entity: "risks.risk",
  route: "/risks/",
  area: "governance",
  columns: ["number", "title", "status"],
  sections: ["overview", "audit-log"],
  seed: { demo: 3, tiers: ["demo", "l"] },
});

const config = (pages = [risks]) =>
  resolveConfig(
    {
      blocks: { memberships: {}, permissions: {}, risks: {} },
      gen: { entityPages: { pages } },
    },
    "/project",
  );

const emit = (pages = [risks]) =>
  new Map(
    emitEntityPages(config(pages), "better-supabase").map((file) => [
      file.path,
      file.contents,
    ]),
  );

describe("ENTITY_PAGE_OUTPUTS", () => {
  it("appends seed, navigation and manifest after forms", () => {
    expect(
      ENTITY_PAGE_OUTPUTS.map((output) => output.id).slice(-4),
    ).toStrictEqual(["forms", "seed", "navigation", "manifest"]);
  });
});

describe("seed output", () => {
  const rows = entityPageSeedRows(resolveEntityPage(config(), risks));

  it("writes one row per demo count, keyed by database column", () => {
    expect(rows).toHaveLength(3);
    expect(Object.keys(rows[0] ?? {}).length).toBeGreaterThan(0);

    for (const key of Object.keys(rows[0] ?? {})) {
      expect(key).toBe(key.toLowerCase());
    }
  });

  it("is repeatable", () => {
    expect(
      entityPageSeedRows(resolveEntityPage(config(), risks)),
    ).toStrictEqual(rows);
  });

  it("writes the module with the tiers", () => {
    const file = [...emit()].find(([path]) => path.endsWith("risks.seed.ts"));

    expect(file?.[1]).toContain("export const risksSeed = {");
    expect(file?.[1]).toContain('tiers: ["demo", "l"]');
    expect(file?.[1]).toContain("satisfies EntitySeed");
  });

  it("writes nothing without seed, and refuses an oversized load", () => {
    const plain = defineEntityPage({ entity: "risks.risk", route: "/risks" });

    expect([...emit([plain])].some(([path]) => path.endsWith(".seed.ts"))).toBe(
      false,
    );

    const huge = defineEntityPage({
      entity: "risks.risk",
      route: "/risks",
      seed: { demo: 501 },
    });

    expect(() => emit([huge])).toThrow(/seed\.demo/);

    const empty = defineEntityPage({
      entity: "risks.risk",
      route: "/risks",
      seed: { demo: 0 },
    });

    expect(() => emit([empty])).toThrow(/seed/);
  });
});

describe("navigation output", () => {
  it("imports the detail href and the first column", () => {
    const file = [...emit()].find(([path]) =>
      path.endsWith("risks.navigation.ts"),
    )?.[1];

    expect(file).toContain('import { risksColumns } from "./risks.columns";');
    expect(file).toContain('import { risksDetail } from "./risks.detail";');
    expect(file).toContain("recordHref: risksDetail.href,");
    expect(file).toContain("titleKey: risksColumns[0].key,");
    expect(file).toContain('area: "governance"');
    expect(file).toContain('href: "/risks"');
  });

  it("writes nothing without an area", () => {
    const plain = defineEntityPage({ entity: "risks.risk", route: "/risks" });

    expect(
      [...emit([plain])].some(([path]) => path.endsWith(".navigation.ts")),
    ).toBe(false);
  });
});

describe("manifest output", () => {
  it("lists every page with its routes and message keys", () => {
    const file = [...emit()].find(([path]) =>
      path.endsWith("routes.manifest.ts"),
    )?.[1];

    expect(file).toContain("detail: risksDetail.route,");
    expect(file).toContain('api: "/api/risks/list"');
    expect(file).toContain('"risks.columns.title"');
    expect(file).toContain('"risks.facets.status"');
  });

  it("names columns, facets, sections and form fields as keys", () => {
    const keys = entityPageMessageKeys(resolveEntityPage(config(), risks));

    expect(keys).toContain("risks.title");
    expect(keys).toContain("risks.sections.audit-log");
    expect(keys.some((key) => key.startsWith("risks.fields."))).toBe(true);
  });

  it("writes no file when there are no pages", () => {
    expect(emitEntityPages(config([]), "better-supabase")).toStrictEqual([]);
  });
});

describe("pages without every part", () => {
  const bare = defineEntityPage({
    entity: "risks.risk",
    route: "/risks",
    area: "governance",
    seed: {},
  });

  const files = emit([bare]);
  const nav = [...files].find(([path]) => path.endsWith("navigation.ts"))?.[1];

  const manifest = [...files].find(([path]) =>
    path.endsWith("routes.manifest.ts"),
  )?.[1];

  it("leaves the record link and title key undefined", () => {
    expect(nav).toContain("recordHref: undefined,");
    expect(nav).toContain("titleKey: undefined,");
    expect(nav).not.toContain("import {");
  });

  it("leaves the detail route undefined in the manifest", () => {
    expect(manifest).toContain("detail: undefined,");
    expect(manifest).not.toContain("import {");
  });

  it("seeds ten rows and the demo tier by default", () => {
    const seed = [...files].find(([path]) => path.endsWith("seed.ts"))?.[1];

    expect(seed).toContain('tiers: ["demo"]');
    expect(seed?.match(/^ {4}\{/gm)).toHaveLength(10);
  });

  it("trims a trailing slash from the routes", () => {
    const slash = defineEntityPage({
      entity: "risks.risk",
      route: "/risks/",
      area: "governance",
    });

    expect(
      [...emit([slash])].find(([path]) => path.endsWith("navigation.ts"))?.[1],
    ).toContain('href: "/risks"');
  });
});

describe("seedValue", () => {
  const field = (spec: Record<string, unknown>) =>
    spec as unknown as Parameters<typeof seedValue>[1];

  it("fills each kind from its bounds", () => {
    expect(seedValue("n", field({ kind: "integer" }), 3)).toBe(3);
    expect(
      seedValue("n", field({ kind: "integer", minimum: 5, maximum: 6 }), 9),
    ).toBe(6);
    expect(seedValue("b", field({ kind: "boolean" }), 1)).toBe(false);
    expect(seedValue("b", field({ kind: "boolean" }), 2)).toBe(true);
    expect(seedValue("e", field({ kind: "enum", values: ["a", "b"] }), 3)).toBe(
      "b",
    );
    expect(seedValue("d", field({ kind: "date" }), 1)).toBe("2026-01-06");
    expect(seedValue("t", field({ kind: "datetime" }), 0)).toBe(
      "2026-01-05T00:00:00.000Z",
    );
    expect(seedValue("u", field({ kind: "uuid" }), 0)).toBe(
      "00000000-0000-4000-8000-000000000001",
    );
    expect(seedValue("j", field({ kind: "json" }), 0)).toBeNull();
  });

  it("names a text value and respects its length", () => {
    expect(seedValue("nextReviewOn", field({ kind: "string" }), 0)).toBe(
      "Next review on 1",
    );
    expect(seedValue("title", field({ kind: "string", maxLength: 3 }), 0)).toBe(
      "Tit",
    );
  });
});
