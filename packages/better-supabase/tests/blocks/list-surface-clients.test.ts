import { describe, expect, it } from "vitest";

import type { BlockTransport } from "../../src/core/block-transport.ts";
import type { EntityList } from "../../src/core/entity-list.ts";

import { createAttachments } from "../../src/blocks/attachments/index.ts";
import { createDocumentTemplates } from "../../src/blocks/document-templates/index.ts";
import { createDrive } from "../../src/blocks/drive/index.ts";
import { createEPrescribing } from "../../src/blocks/e-prescribing/index.ts";
import { createEmployees } from "../../src/blocks/employees/index.ts";
import { createEnrollments } from "../../src/blocks/enrollments/index.ts";
import { createForms } from "../../src/blocks/forms/index.ts";
import { createInventory } from "../../src/blocks/inventory/index.ts";
import { createLeave } from "../../src/blocks/leave/index.ts";
import { createPasses } from "../../src/blocks/passes/index.ts";
import { createPayrollExport } from "../../src/blocks/payroll-export/index.ts";
import { createQualifications } from "../../src/blocks/qualifications/index.ts";
import { createSequences } from "../../src/blocks/sequences/index.ts";
import { createSignatures } from "../../src/blocks/signatures/index.ts";
import { createTemplates } from "../../src/blocks/templates/index.ts";
import { createVersions } from "../../src/blocks/versions/index.ts";
import { fieldsTransport } from "./fields-transport.ts";

interface Case {
  readonly label: string;
  readonly fn: string;
  readonly sort: string;
  readonly filter: string;
  readonly facet: string;
  /** Whether the entity declares `search`, so `q` is accepted. */
  readonly searchable?: boolean;
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
    searchable: true,
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
    label: "document-templates",
    searchable: true,
    fn: "page_document_templates",
    sort: "updatedAt",
    filter: "documentType",
    facet: "active",
    list: (transport) => {
      const client = createDocumentTemplates(options(transport));

      return {
        page: (page) => client.templatePage(page),
        facets: (facets) => client.templateFacets(facets),
        count: (count) => client.templateCount(count),
      };
    },
  },
  {
    label: "leave",
    searchable: true,
    fn: "page_leave_requests",
    sort: "endsOn",
    filter: "status",
    facet: "typeId",
    list: (transport) => {
      const client = createLeave(options(transport));

      return {
        page: (page) => client.requestPage(page),
        facets: (facets) => client.requestFacets(facets),
        count: (count) => client.requestCount(count),
      };
    },
  },
  {
    label: "employees",
    searchable: true,
    fn: "page_employees",
    sort: "startDate",
    filter: "status",
    facet: "teamId",
    list: (transport) => {
      const client = createEmployees(options(transport));
      const organizationId = "org-1";

      return {
        page: (page) => client.page({ ...page, organizationId }),
        facets: (facets) => client.facets({ ...facets, organizationId }),
        count: (count) => client.count({ ...count, organizationId }),
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
  {
    label: "signatures",
    searchable: true,
    fn: "page_signature_requests",
    sort: "createdAt",
    filter: "status",
    facet: "status",
    list: (transport) => {
      const client = createSignatures(options(transport));

      return {
        page: (page) => client.requestPage(page),
        facets: (facets) => client.requestFacets(facets),
        count: (count) => client.requestCount(count),
      };
    },
  },
  {
    label: "qualifications",
    searchable: true,
    fn: "page_qualification_types",
    sort: "name",
    filter: "state",
    facet: "expiry",
    list: (transport) => {
      const client = createQualifications(options(transport));

      return {
        page: (page) => client.typePage({ ...page, organizationId: "org-1" }),
        facets: (facets) =>
          client.typeFacets({ ...facets, organizationId: "org-1" }),
        count: (count) =>
          client.typeCount({ ...count, organizationId: "org-1" }),
      };
    },
  },
  {
    label: "versions",
    searchable: true,
    fn: "page_versions",
    sort: "createdAt",
    filter: "source",
    facet: "subjectType",
    list: (transport) => {
      const client = createVersions(options(transport));

      return {
        page: (page) => client.versionPage(page),
        facets: (facets) => client.versionFacets(facets),
        count: (count) => client.versionCount(count),
      };
    },
  },
  {
    label: "attachments",
    searchable: true,
    fn: "page_attachments",
    sort: "createdAt",
    filter: "status",
    facet: "subjectType",
    list: (transport) => {
      const client = createAttachments(options(transport));

      return {
        page: (page) => client.attachmentPage(page),
        facets: (facets) => client.attachmentFacets(facets),
        count: (count) => client.attachmentCount(count),
      };
    },
  },
  {
    label: "templates",
    searchable: true,
    fn: "page_templates",
    sort: "name",
    filter: "type",
    facet: "language",
    list: (transport) => {
      const client = createTemplates(options(transport));

      return {
        page: (page) =>
          client.templatePage({ ...page, organizationId: "org-1" }),
        facets: (facets) =>
          client.templateFacets({ ...facets, organizationId: "org-1" }),
        count: (count) =>
          client.templateCount({ ...count, organizationId: "org-1" }),
      };
    },
  },
  {
    label: "forms submissions",
    searchable: true,
    fn: "page_form_submissions",
    sort: "createdAt",
    filter: "status",
    facet: "formId",
    list: (transport) => {
      const client = createForms(options(transport));

      return {
        page: (page) =>
          client.submissionPage({ ...page, organizationId: "org-1" }),
        facets: (facets) =>
          client.submissionFacets({ ...facets, organizationId: "org-1" }),
        count: (count) =>
          client.submissionCount({ ...count, organizationId: "org-1" }),
      };
    },
  },
  {
    label: "drive documents",
    searchable: true,
    fn: "page_drive_documents",
    sort: "number",
    filter: "status",
    facet: "type",
    list: (transport) => {
      const client = createDrive(options(transport));
      const organizationId = "org-1";

      return {
        page: (page) => client.documentPage({ ...page, organizationId }),
        facets: (facets) =>
          client.documentFacets({ ...facets, organizationId }),
        count: (count) => client.documentCount({ ...count, organizationId }),
      };
    },
  },
  {
    label: "inventory levels",
    searchable: true,
    fn: "page_inventory_levels",
    sort: "available",
    filter: "status",
    facet: "locationId",
    list: (transport) => {
      const client = createInventory(options(transport));
      const organizationId = "org-1";

      return {
        page: (page) => client.levelPage({ ...page, organizationId }),
        facets: (facets) => client.levelFacets({ ...facets, organizationId }),
        count: (count) => client.levelCount({ ...count, organizationId }),
      };
    },
  },
  {
    label: "inventory movements",
    searchable: true,
    fn: "page_inventory_movements",
    sort: "effectiveAt",
    filter: "kind",
    facet: "locationId",
    list: (transport) => {
      const client = createInventory(options(transport));
      const organizationId = "org-1";

      return {
        page: (page) => client.movementPage({ ...page, organizationId }),
        facets: (facets) =>
          client.movementFacets({ ...facets, organizationId }),
        count: (count) => client.movementCount({ ...count, organizationId }),
      };
    },
  },
  {
    label: "inventory lots",
    searchable: true,
    fn: "page_inventory_lots",
    sort: "expiresOn",
    filter: "expiry",
    facet: "locationId",
    list: (transport) => {
      const client = createInventory(options(transport));
      const organizationId = "org-1";

      return {
        page: (page) => client.lotPage({ ...page, organizationId }),
        facets: (facets) => client.lotFacets({ ...facets, organizationId }),
        count: (count) => client.lotCount({ ...count, organizationId }),
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
