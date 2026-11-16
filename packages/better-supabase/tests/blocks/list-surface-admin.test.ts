import { describe, expect, it } from "vitest";

import type { BlockTransport } from "../../src/core/block-transport.ts";
import type { EntityList } from "../../src/core/entity-list.ts";

import { createCompliance } from "../../src/blocks/compliance/index.ts";
import { createConsents } from "../../src/blocks/consents/index.ts";
import { createDataLifecycle } from "../../src/blocks/data-lifecycle/index.ts";
import { createImpersonation } from "../../src/blocks/impersonation/index.ts";
import { createOptionSets } from "../../src/blocks/option-sets/index.ts";
import { createSequences } from "../../src/blocks/sequences/index.ts";
import { fieldsTransport } from "./fields-transport.ts";

interface Case {
  readonly label: string;
  readonly fn: string;
  readonly sort: string;
  readonly filter: string;
  readonly facet: string;
  /** Whether the entity declares `search`, so `q` is accepted. */
  readonly searchable?: boolean;
  /** A platform-wide list: the call sends no organization. */
  readonly tenantless?: boolean;
  readonly list: (transport: BlockTransport) => EntityList<unknown>;
}

const ORG = { organizationId: "org-1" };

const tenantArg = (spec: Case) =>
  spec.tenantless === true ? {} : { tenant: "org-1" };

// The automation and admin blocks (family F7 and F8) page through the same
// client contract as the other lists; this file runs the shared checks over them.
const CASES: readonly Case[] = [
  {
    label: "option sets",
    searchable: true,
    fn: "page_option_sets",
    sort: "name",
    filter: "field",
    facet: "field",
    list: (transport) => {
      const client = createOptionSets({ transport });

      return {
        page: (page) => client.setPage({ ...page, ...ORG }),
        facets: (facets) => client.setFacets({ ...facets, ...ORG }),
        count: (count) => client.setCount({ ...count, ...ORG }),
      };
    },
  },
  {
    label: "support sessions",
    tenantless: true,
    fn: "page_support_sessions",
    sort: "startedAt",
    filter: "adminId",
    facet: "readOnly",
    list: (transport) => {
      const client = createImpersonation({ transport });

      return {
        page: (page) => client.sessionPage(page),
        facets: (facets) => client.sessionFacets(facets),
        count: (count) => client.sessionCount(count),
      };
    },
  },
  {
    label: "consent purposes",
    searchable: true,
    fn: "page_consent_purposes",
    sort: "key",
    filter: "legalBasis",
    facet: "legalBasis",
    list: (transport) => {
      const client = createConsents({ transport, tenant: "org-1" });

      return {
        page: (page) => client.purposePage(page),
        facets: (facets) => client.purposeFacets(facets),
        count: (count) => client.purposeCount(count),
      };
    },
  },
  {
    label: "control frameworks",
    searchable: true,
    fn: "page_control_frameworks",
    sort: "name",
    filter: "kind",
    facet: "kind",
    list: (transport) => {
      const client = createCompliance({ transport });

      return {
        page: (page) => client.frameworkPage({ ...page, ...ORG }),
        facets: (facets) => client.frameworkFacets({ ...facets, ...ORG }),
        count: (count) => client.frameworkCount({ ...count, ...ORG }),
      };
    },
  },
  {
    label: "evidence tasks",
    searchable: true,
    fn: "page_evidence_tasks",
    sort: "dueOn",
    filter: "controlId",
    facet: "controlId",
    list: (transport) => {
      const client = createCompliance({ transport });

      return {
        page: (page) => client.evidenceTaskPage({ ...page, ...ORG }),
        facets: (facets) => client.evidenceTaskFacets({ ...facets, ...ORG }),
        count: (count) => client.evidenceTaskCount({ ...count, ...ORG }),
      };
    },
  },
  {
    label: "compliance policies",
    searchable: true,
    fn: "page_compliance_policies",
    sort: "title",
    filter: "ownerId",
    facet: "requiresAcknowledgement",
    list: (transport) => {
      const client = createCompliance({ transport });

      return {
        page: (page) => client.policyPage({ ...page, ...ORG }),
        facets: (facets) => client.policyFacets({ ...facets, ...ORG }),
        count: (count) => client.policyCount({ ...count, ...ORG }),
      };
    },
  },
  {
    label: "data subject requests",
    searchable: true,
    fn: "page_data_subject_requests",
    sort: "dueAt",
    filter: "status",
    facet: "status",
    list: (transport) => {
      const client = createDataLifecycle({ transport });

      return {
        page: (page) => client.subjectRequestPage({ ...page, ...ORG }),
        facets: (facets) => client.subjectRequestFacets({ ...facets, ...ORG }),
        count: (count) => client.subjectRequestCount({ ...count, ...ORG }),
      };
    },
  },
  {
    label: "sequence enrollments",
    fn: "page_sequence_enrollments",
    sort: "enrolledAt",
    filter: "status",
    facet: "status",
    list: (transport) => {
      const client = createSequences({ transport, tenant: "org-1" });

      return {
        page: (page) => client.enrollmentPage(page),
        facets: (facets) => client.enrollmentFacets(facets),
        count: (count) => client.enrollmentCount(count),
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

    expect(page).toEqual({
      items: [],
      hasMore: true,
      nextCursor: ["a", "b"],
      sorted: { applied: [{ by: spec.sort, direction: "asc" }], ignored: [] },
    });

    expect(transport.calls).toEqual([
      [
        spec.fn,
        {
          ...tenantArg(spec),
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
          ...tenantArg(spec),
          filters: { [spec.filter]: ["one"], facet: spec.facet },
        },
      ],
    ]);
  });

  it("sends the text search of a searchable entity", async () => {
    if (spec.searchable !== true) {
      return;
    }

    const transport = fieldsTransport({
      [spec.fn]: () => ({ items: [], hasMore: false }),
    });

    await spec.list(transport).page({ q: "text" }).orThrow();

    expect(transport.calls[0]?.[1]).toMatchObject({
      filters: { search: "text" },
    });
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
        {
          ...tenantArg(spec),
          filters: { [spec.filter]: ["one"], count: true },
        },
      ],
    ]);
  });

  it("rejects a sort, filter, facet or text the entity does not declare", async () => {
    const transport = fieldsTransport({});
    const list = spec.list(transport);

    const results = [
      await list.page({ sort: { by: "colour" } }),
      await list.page({ filters: { colour: ["red"] } }),
      await list.facets({ facets: ["colour"] }),
      ...(spec.searchable === true ? [] : [await list.page({ q: "text" })]),
    ];

    for (const result of results) {
      expect(result.ok).toBe(false);
      expect(result.error?.kind).toBe("invalid_input");
    }

    expect(transport.calls).toEqual([]);
  });
});
