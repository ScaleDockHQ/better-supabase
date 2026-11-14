import { describe, expect, it } from "vitest";

import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";
import type {
  Catalog,
  CatalogTable,
  Snapshot,
} from "../../../src/cli/introspect/types.ts";

import { parseSnapshot } from "../../../src/cli/commands/snapshot.ts";
import { RULES, runRules } from "../../../src/cli/doctor/rules.ts";
import { toCatalog } from "../../../src/cli/introspect/catalog.ts";
import { fromCatalog } from "../../../src/cli/introspect/from-catalog.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { defineEntityPage } from "../../../src/list/entity-page.ts";
import { moduleSnapshotFixture as fixture } from "../fixtures/library.ts";

const base = await parseSnapshot(fixture);

type Mutable<T> = { -readonly [K in keyof T]: T[K] };

const index = (
  name: string,
  columns: string[],
  extra: Partial<CatalogTable["indexes"][number]> = {},
): CatalogTable["indexes"][number] => ({
  name,
  columns,
  unique: false,
  primary: false,
  partial: false,
  method: "btree",
  predicate: null,
  ...extra,
});

/** The fixture with a `better_supabase.risks` table that holds `indexes`. */
function withRisks(...indexes: CatalogTable["indexes"]): Snapshot {
  const copy = structuredClone(toCatalog(base)) as Mutable<Catalog>;

  const template = copy.tables.find((table) => table.name === "notes");

  copy.tables = [
    ...copy.tables,
    {
      ...structuredClone(template!),
      schema: "better_supabase",
      name: "risks",
      indexes,
    },
  ];

  return fromCatalog(copy);
}

const context = (snapshot: Snapshot, pages = true): DoctorContext => ({
  config: resolveConfig(
    {
      blocks: { memberships: {}, permissions: {}, risks: {} },
      ...(pages
        ? {
            gen: {
              entityPages: {
                pages: [
                  defineEntityPage({ entity: "risks.risk", route: "/risks" }),
                ],
              },
            },
          }
        : {}),
    },
    "/project",
  ),
  snapshot,
  configToml: undefined,
  envFiles: [],
  gitignore: "",
  sources: [],
});

const run = (ctx: DoctorContext) =>
  runRules(
    ctx,
    RULES.filter((rule) => rule.code === "BS636"),
  );

const COVERING = [
  index("risks_score", ["tenant_id", "residual_score", "id"]),
  index("risks_number", ["tenant_id", "number", "id"]),
  index("risks_review", ["tenant_id", "next_review_on", "id"]),
  index("risks_status", ["tenant_id", "status"]),
  index("risks_category", ["category"]),
];

describe("BS636 entity page indexes", () => {
  it("flags each sort and facet without an index", async () => {
    const findings = await run(
      context(withRisks(index("risks_pkey", ["id"], { primary: true }))),
    );

    expect(findings.map((finding) => finding.target)).toStrictEqual([
      "better_supabase.risks:sort:residualScore",
      "better_supabase.risks:sort:number",
      "better_supabase.risks:sort:nextReviewOn",
      "better_supabase.risks:facet:status",
      "better_supabase.risks:facet:category",
    ]);

    expect(findings[0]?.message).toContain("risks.risk lists with sort");
    expect(findings[0]?.message).toContain("after tenant_id");
  });

  it("names only the entries a partial index set leaves out", async () => {
    const findings = await run(
      context(withRisks(...COVERING.slice(0, 3), index("p", ["tenant_id"]))),
    );

    expect(findings.map((finding) => finding.target)).toStrictEqual([
      "better_supabase.risks:facet:status",
      "better_supabase.risks:facet:category",
    ]);
  });

  it("accepts an index that leads with the column or follows the tenant", async () => {
    expect(await run(context(withRisks(...COVERING)))).toStrictEqual([]);
  });

  it("ignores a partial index", async () => {
    const findings = await run(
      context(
        withRisks(
          ...COVERING.slice(0, 4),
          index("risks_category", ["tenant_id", "category"], { partial: true }),
        ),
      ),
    );

    expect(findings.map((finding) => finding.target)).toStrictEqual([
      "better_supabase.risks:facet:category",
    ]);
  });

  it("does nothing without pages or without the table", async () => {
    expect(await run(context(withRisks(), false))).toStrictEqual([]);
    expect(await run(context(base))).toStrictEqual([]);
  });
});
