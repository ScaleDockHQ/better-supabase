import { Pool } from "pg";
import { afterAll, describe, it } from "vitest";

import type { FilterQuery } from "../../src/list/index.ts";
import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import {
  createAutomationsAdmin,
  defineRuleFields,
} from "../../src/blocks/automations/index.ts";
import { createContacts } from "../../src/blocks/contacts/index.ts";
import { createSegments } from "../../src/blocks/segments/index.ts";
import { withBlockSubjects } from "../../src/config/block-subjects.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { testBlockList } from "../../src/testing/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const layout: BlockSqlLayout = {
  subjects: withBlockSubjects({}, ["contacts"], {}),
};

const MODULES = [
  "organizations",
  "outbox",
  "subjects",
  "automations",
  "contacts",
  "segments",
];

const lifecycleFields = {
  lifecycle: { type: "select", options: ["lead", "customer"] },
} as const;

const lifecycleIs = (value: string): FilterQuery => ({
  id: "root",
  type: "group",
  combinator: "and",
  rules: [
    { id: "r1", type: "rule", path: ["lifecycle"], operator: "is", value },
  ],
});

describe.skipIf(!live)("the CRM block lists follow the list contract", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("pages companies and segments the same way", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("crm-lists-owner");
      await s.install(MODULES, layout);
      const org = await s.organization(owner);
      await s.service();

      for (const subject of ["company", "person"]) {
        await createAutomationsAdmin({ transport: sqlTransport(s.sql) })
          .syncFields(defineRuleFields(subject, lifecycleFields))
          .orThrow();
      }

      await s.as(owner);

      const contacts = createContacts({ transport: sqlTransport(s.sql) });
      const segments = createSegments({ transport: sqlTransport(s.sql) });

      const lifecycles = ["lead", "lead", "customer", "customer", "customer"];

      for (const [index, lifecycle] of lifecycles.entries()) {
        await contacts
          .saveCompany({
            organizationId: org,
            input: {
              name: `${index < 2 ? "Holiday" : "Other"} company ${String(index)}`,
              lifecycle,
            },
          })
          .orThrow();
      }

      for (const [index, lifecycle] of lifecycles.entries()) {
        await segments
          .upsert({
            organizationId: org,
            segment: {
              subjectType: index < 2 ? "company" : "person",
              name: `${index < 2 ? "Holiday" : "Other"} segment ${String(index)}`,
              conditions: lifecycleIs(lifecycle),
            },
          })
          .orThrow();
      }

      await testBlockList({
        name: "contacts.companies",
        target: {
          page: (options) =>
            contacts.companyPage({ ...options, organizationId: org }),
          count: (options) =>
            contacts.companyCount({ ...options, organizationId: org }),
          facets: (options) =>
            contacts.companyFacets({ ...options, organizationId: org }),
          get: (id) => contacts.companyById(id),
        },
        rows: 5,
        sorts: ["name"],
        facets: { lifecycle: { lead: 2, customer: 3 } },
        arrayFilter: { column: "lifecycle", values: ["lead", "customer"] },
        search: "Holiday",
      });

      await testBlockList({
        name: "segments",
        target: {
          page: (options) => segments.page({ ...options, organizationId: org }),
          count: (options) =>
            segments.count({ ...options, organizationId: org }),
          facets: (options) =>
            segments.facets({ ...options, organizationId: org }),
          get: (id) => segments.getSegment(id),
        },
        rows: 5,
        sorts: ["name"],
        facets: { subjectType: { company: 2, person: 3 } },
        arrayFilter: { column: "subjectType", values: ["company", "person"] },
        search: "Holiday",
      });
    } finally {
      await s.close();
    }
  });
});
