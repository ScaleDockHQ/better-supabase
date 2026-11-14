import { describe, expect, it } from "vitest";

import { agentCheckoutBlock } from "../../src/blocks/agent-checkout/manifest.ts";
import { appraisalsBlock } from "../../src/blocks/appraisals/manifest.ts";
import { commissionsBlock } from "../../src/blocks/commissions/manifest.ts";
import { contentBlock } from "../../src/blocks/content/manifest.ts";
import { coursesBlock } from "../../src/blocks/courses/manifest.ts";
import { damBlock } from "../../src/blocks/dam/manifest.ts";
import { donationsBlock } from "../../src/blocks/donations/manifest.ts";
import { leasesBlock } from "../../src/blocks/leases/manifest.ts";
import { inspectionsBlock } from "../../src/blocks/inspections/manifest.ts";
import { legalEntitiesBlock } from "../../src/blocks/legal-entities/manifest.ts";
import { limsBlock } from "../../src/blocks/lims/manifest.ts";
import { maintenanceBlock } from "../../src/blocks/maintenance/manifest.ts";
import { manufacturingBlock } from "../../src/blocks/manufacturing/manifest.ts";
import { periodsBlock } from "../../src/blocks/periods/manifest.ts";
import { referralsBlock } from "../../src/blocks/referrals/manifest.ts";
import { meetingsBlock } from "../../src/blocks/meetings/manifest.ts";
import { rfqsBlock } from "../../src/blocks/rfqs/manifest.ts";
import { risksBlock } from "../../src/blocks/risks/manifest.ts";
import { shipmentsBlock } from "../../src/blocks/shipments/manifest.ts";
import { tillsBlock } from "../../src/blocks/tills/manifest.ts";
import { warehouseBlock } from "../../src/blocks/warehouse/manifest.ts";
import { warrantyBlock } from "../../src/blocks/warranty/manifest.ts";
import { SQL_MODULES } from "../../src/sql/registry.ts";
import { renderBlocks } from "../../src/sql/render.ts";

const BLOCKS = [
  agentCheckoutBlock,
  appraisalsBlock,
  commissionsBlock,
  contentBlock,
  coursesBlock,
  damBlock,
  donationsBlock,
  leasesBlock,
  inspectionsBlock,
  legalEntitiesBlock,
  limsBlock,
  maintenanceBlock,
  manufacturingBlock,
  periodsBlock,
  referralsBlock,
  meetingsBlock,
  rfqsBlock,
  risksBlock,
  shipmentsBlock,
  tillsBlock,
  warehouseBlock,
  warrantyBlock,
];

const RENDERED = renderBlocks(
  Object.keys(SQL_MODULES).filter((name) => name !== "pgtap"),
  {},
);

const sqlOf = (modules: readonly string[]): string =>
  RENDERED.filter((file) => modules.includes(file.module))
    .map((file) => file.contents)
    .join("\n");

// The manifest and the SQL list function each name the sorts, facets and
// filters of a list entity (ADR 0749). This keeps the two declarations equal.
const CASES = BLOCKS.flatMap((block) =>
  Object.entries(block.entities)
    .filter(([, surface]) => surface.sorts !== undefined)
    .map(([entity, surface]) => ({
      label: `${block.name} ${entity}`,
      sql: sqlOf(block.sql),
      surface,
    })),
);

describe("list surface of the blocks that page", () => {
  describe.each(CASES)("$label", ({ sql, surface }) => {
    it("implements every declared sort in SQL", () => {
      for (const sort of surface.sorts ?? []) {
        expect(sql).toContain(`v_sort = '${sort}'`);
      }
    });

    it("implements every declared facet in SQL", () => {
      for (const facet of surface.facets ?? []) {
        expect(sql).toContain(`when '${facet}' then`);
      }
    });

    it("reads every declared filter in SQL", () => {
      for (const filter of surface.filters ?? []) {
        expect(sql).toMatch(
          new RegExp(`v_filters (->|->>) '${filter}'|\\{${filter},0\\}`),
        );
      }
    });
  });

  it("reads the search text where an entity declares search", () => {
    const risks = Object.values(risksBlock.entities).filter(
      (surface) => surface.search !== undefined,
    );

    expect(risks).toHaveLength(1);
    expect(sqlOf(risksBlock.sql)).toContain("v_filters ->> 'search'");
  });

  it("declares the surface on every block that pages", () => {
    expect(CASES).toHaveLength(28);
  });
});
