import { describe, expect, it } from "vitest";

import type { BlockTransport } from "../../src/core/block-transport.ts";
import type { EntityList } from "../../src/core/entity-list.ts";

import { createEPrescribing } from "../../src/blocks/e-prescribing/index.ts";
import { createEnrollments } from "../../src/blocks/enrollments/index.ts";
import { createPasses } from "../../src/blocks/passes/index.ts";
import { createPayrollExport } from "../../src/blocks/payroll-export/index.ts";
import { createSequences } from "../../src/blocks/sequences/index.ts";
import { fieldsTransport } from "./fields-transport.ts";

interface Case {
  readonly label: string;
  readonly fn: string;
  readonly sort: string;
  readonly filter: string;
  readonly facet: string;
  readonly list: (transport: BlockTransport) => EntityList<unknown>;
}

const options = (transport: BlockTransport) => ({ transport, tenant: "org-1" });

const CASES: readonly Case[] = [
  {
    label: "sequences",
    fn: "page_sequences",
    sort: "updatedAt",
    filter: "status",
    facet: "status",
    list: (transport) => {
      const client = createSequences(options(transport));

      return {
        page: (page) => client.sequencePage(page),
        facets: (facets) => client.sequenceFacets(facets),
        count: (count) => client.sequenceCount(count),
      };
    },
  },
  {
    label: "payroll-export",
    fn: "page_payroll_runs",
    sort: "createdAt",
    filter: "status",
    facet: "status",
    list: (transport) => {
      const client = createPayrollExport(options(transport));

      return {
        page: (page) => client.runPage(page),
        facets: (facets) => client.runFacets(facets),
        count: (count) => client.runCount(count),
      };
    },
  },
  {
    label: "passes",
    fn: "page_passes",
    sort: "validUntil",
    filter: "holderUserId",
    facet: "status",
    list: (transport) => {
      const client = createPasses(options(transport));

      return {
        page: (page) => client.passPage(page),
        facets: (facets) => client.passFacets(facets),
        count: (count) => client.passCount(count),
      };
    },
  },
  {
    label: "enrollments",
    fn: "page_enrollments",
    sort: "enrolledAt",
    filter: "program",
    facet: "program",
    list: (transport) => {
      const client = createEnrollments(options(transport));

      return {
        page: (page) => client.enrollmentPage(page),
        facets: (facets) => client.enrollmentFacets(facets),
        count: (count) => client.enrollmentCount(count),
      };
    },
  },
  {
    label: "e-prescribing",
    fn: "list_prescriptions",
    sort: "signedAt",
    filter: "prescriberId",
    facet: "status",
    list: (transport) => {
      const client = createEPrescribing(options(transport));

      return {
        page: (page) => client.prescriptionPage(page),
        facets: (facets) => client.prescriptionFacets(facets),
        count: (count) => client.prescriptionCount(count),
      };
    },
  },
];

describe.each(CASES)("list surface client of $label", (spec) => {
  it("pages with a sort, a list filter and a cursor", async () => {
    const transport = fieldsTransport({
      [spec.fn]: () => ({ items: [], hasMore: true, nextCursor: ["a", "b"] }),
    });

    const page = await spec
      .list(transport)
      .page({
        limit: 5,
        after: ["x", "y"],
        sort: { by: spec.sort, direction: "asc" },
        filters: { [spec.filter]: ["one", "two"] },
      })
      .orThrow();

    expect(page).toEqual({ items: [], hasMore: true, nextCursor: ["a", "b"] });

    expect(transport.calls).toEqual([
      [
        spec.fn,
        {
          tenant: "org-1",
          filters: {
            sort: spec.sort,
            direction: "asc",
            [spec.filter]: ["one", "two"],
            after: ["x", "y"],
            limit: 5,
            paged: true,
          },
        },
      ],
    ]);
  });

  it("counts a facet under the page filters", async () => {
    const transport = fieldsTransport({
      [spec.fn]: () => ({
        facet: spec.facet,
        values: [{ value: "a", count: { value: 2, exact: true } }],
      }),
    });

    await expect(
      spec
        .list(transport)
        .facets({ facets: [spec.facet], filters: { [spec.filter]: ["one"] } })
        .orThrow(),
    ).resolves.toEqual([
      {
        facet: spec.facet,
        values: [{ value: "a", count: { value: 2, exact: true } }],
      },
    ]);

    expect(transport.calls).toEqual([
      [
        spec.fn,
        {
          tenant: "org-1",
          filters: { [spec.filter]: ["one"], facet: spec.facet },
        },
      ],
    ]);
  });

  it("counts the rows that match", async () => {
    const transport = fieldsTransport({
      [spec.fn]: () => ({ value: 7, exact: false }),
    });

    await expect(
      spec
        .list(transport)
        .count({ filters: { [spec.filter]: ["one"] } })
        .orThrow(),
    ).resolves.toEqual({ value: 7, exact: false });

    expect(transport.calls).toEqual([
      [
        spec.fn,
        { tenant: "org-1", filters: { [spec.filter]: ["one"], count: true } },
      ],
    ]);
  });

  it("rejects a sort, filter, facet or text the entity does not declare", async () => {
    const transport = fieldsTransport({});
    const list = spec.list(transport);

    const results = [
      await list.page({ sort: { by: "colour" } }),
      await list.page({ filters: { colour: ["red"] } }),
      await list.page({ q: "text" }),
      await list.facets({ facets: ["colour"] }),
    ];

    for (const result of results) {
      expect(result.ok).toBe(false);
      expect(result.error?.kind).toBe("invalid_input");
    }

    expect(transport.calls).toEqual([]);
  });
});
