import { describe, expect, it } from "vitest";

import {
  entityPageMessageKeys,
  entityPageSeedRows,
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
