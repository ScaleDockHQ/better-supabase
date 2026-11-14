import { describe, expect, it } from "vitest";

import type { BlocksInput } from "../../../src/config/index.ts";

import {
  emitEntityPages,
  ENTITY_PAGE_OUTPUTS,
  entityPageIndexes,
  entityPageIndexSql,
  entityPageName,
  resolveEntityPage,
  resolveEntityPages,
} from "../../../src/cli/gen/entity-pages.ts";
import { resolveConfig } from "../../../src/config/resolve.ts";
import { defineEntityPage } from "../../../src/list/entity-page.ts";

const risks = defineEntityPage({
  entity: "risks.risk",
  route: "/risks",
  list: { pageSize: 25 },
});

const INSTALLED: BlocksInput = { memberships: {}, permissions: {}, risks: {} };

const config = (
  pages = [risks],
  entityPages: object = {},
  blocks: BlocksInput = INSTALLED,
) =>
  resolveConfig(
    { blocks, gen: { entityPages: { pages, ...entityPages } } },
    "/project",
  );

describe("resolveEntityPage", () => {
  it("reads the sorts, facets and table from the block", () => {
    const resolved = resolveEntityPage(config(), risks);

    expect(resolved.name).toBe("risks");
    expect(resolved.reads).toBe("risks");
    expect(resolved.surface.sorts).toStrictEqual([
      "residualScore",
      "number",
      "nextReviewOn",
    ]);

    expect(resolved.surface.facets).toStrictEqual([
      "status",
      "category",
      "band",
    ]);

    expect(resolved.table?.name).toBe("risks");
    expect(resolved.table?.tenant).toBe("tenant_id");
  });

  it("names a missing block and an entity without a list", () => {
    expect(() =>
      resolveEntityPage(
        config([risks], {}, { memberships: {}, permissions: {} }),
        risks,
      ),
    ).toThrow(/block "risks" is not installed/);

    expect(() =>
      resolveEntityPage(
        config(),
        defineEntityPage({ entity: "risks.risk_assessment", route: "/a" }),
      ),
    ).toThrow(/declares no list for "risk_assessment"/);
  });

  it("refuses two pages with one name", () => {
    expect(() =>
      resolveEntityPages(
        config([
          risks,
          defineEntityPage({ entity: "risks.risk", route: "/x/risks" }),
        ]),
      ),
    ).toThrow(/two pages are named "risks"/);
  });

  it("names a page by its route unless it sets a name", () => {
    expect(entityPageName(risks)).toBe("risks");
    expect(entityPageName({ ...risks, name: "register" })).toBe("register");
  });
});

describe("entityPageIndexes", () => {
  it("indexes each sort and facet that is a column, tenant first", () => {
    const indexes = entityPageIndexes(resolveEntityPage(config(), risks));

    expect(indexes.map((index) => index.columns)).toStrictEqual([
      ["tenant_id", "residual_score", "id"],
      ["tenant_id", "number", "id"],
      ["tenant_id", "next_review_on", "id"],
      ["tenant_id", "status"],
      ["tenant_id", "category"],
    ]);
  });

  it("writes one re-runnable statement per index", () => {
    const sql = entityPageIndexSql(config());

    expect(sql).toContain(
      'create index if not exists "risks_tenant_id_residual_score_id_page_idx" on "better_supabase"."risks" ("tenant_id", "residual_score", "id");',
    );

    expect(sql?.match(/create index/g)).toHaveLength(5);
  });

  it("writes nothing without pages", () => {
    expect(
      entityPageIndexSql(resolveConfig({ blocks: { risks: {} } }, "/project")),
    ).toBeUndefined();
  });
});

describe("emitEntityPages", () => {
  const files = emitEntityPages(config(), "better-supabase");
  const byPath = new Map(files.map((file) => [file.path, file.contents]));

  it("writes the list query, the route, the scale file and the schema indexes", () => {
    expect([...byPath.keys()].toSorted()).toStrictEqual([
      "app/api/risks/list/route.ts",
      "src/lib/supabase/pages/risks.list.ts",
      "supabase/schemas/entity_page_indexes.sql",
      "supabase/tests/scale/scale_list_risks.test.sql",
    ]);
  });

  it("declares the surface in the list query", () => {
    const list = byPath.get("src/lib/supabase/pages/risks.list.ts");

    expect(list).toContain(
      'import { defineEntityListQuery } from "better-supabase/list";',
    );
    expect(list).toContain(
      'sorts: ["residualScore", "number", "nextReviewOn"]',
    );
    expect(list).toContain("search: true,");
    expect(list).toContain('{ entity: "risks.risk", pageSize: 25 }');
  });

  it("runs the list in the route", () => {
    const route = byPath.get("app/api/risks/list/route.ts");

    expect(route).toContain(
      'from "../../../../src/lib/supabase/pages/risks.list"',
    );
    expect(route).toContain(
      'import { bsbCore as bsb } from "@/lib/supabase/server-core";',
    );
    expect(route).toContain("page: (options) => db.risks.page(options),");
    expect(route).toContain("facets: (options) => db.risks.facets(options),");
    expect(route).toContain("status: 400");
  });

  it("plans each sort and facet in the scale file", () => {
    const scale = byPath.get("supabase/tests/scale/scale_list_risks.test.sql");

    expect(scale).toContain("select plan(5);");
    expect(scale).toContain("set local enable_seqscan = off;");
    expect(scale).toContain('order by "residual_score", id limit 50');
    expect(scale).toContain('group by "status"');
  });

  it("honours the app directory, server module and scale folder", () => {
    const custom = emitEntityPages(
      config([risks], {
        appDir: "web/app",
        server: { module: "~/server", export: "serverCore" },
        scaleDir: "db/scale",
      }),
      "better-supabase",
    );

    const paths = custom.map((file) => file.path);

    expect(paths).toContain("web/app/api/risks/list/route.ts");
    expect(paths).toContain("db/scale/scale_list_risks.test.sql");

    expect(
      custom.find((file) => file.path.endsWith("route.ts"))?.contents,
    ).toContain('import { serverCore as bsb } from "~/server";');
  });

  it("calls the methods a page names on the reads it names", () => {
    const named = emitEntityPages(
      config([
        defineEntityPage({
          entity: "risks.risk",
          route: "/risks",
          reads: "grc",
          methods: { page: "riskPage", facets: "riskFacets" },
        }),
      ]),
      "better-supabase",
    );

    const route = named.find((file) => file.path.endsWith("route.ts"));

    expect(route?.contents).toContain("db.grc.riskPage(options)");
    expect(route?.contents).toContain("db.grc.riskFacets(options)");
  });

  it("lists the outputs later lanes extend", () => {
    expect(ENTITY_PAGE_OUTPUTS.map((output) => output.id)).toStrictEqual([
      "list-query",
      "list-route",
      "scale-test",
    ]);

    expect(
      ENTITY_PAGE_OUTPUTS.map((output) => output.apiVersion),
    ).toStrictEqual([1, 1, 1]);
  });

  it("writes nothing without pages", () => {
    expect(
      emitEntityPages(
        resolveConfig({ blocks: { risks: {} } }, "/project"),
        "better-supabase",
      ),
    ).toStrictEqual([]);
  });
});
