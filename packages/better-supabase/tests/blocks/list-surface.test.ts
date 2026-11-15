import { describe, expect, it } from "vitest";

import { accessRequestsBlock } from "../../src/blocks/access-requests/manifest.ts";
import { accountingBlock } from "../../src/blocks/accounting/manifest.ts";
import { agentCheckoutBlock } from "../../src/blocks/agent-checkout/manifest.ts";
import { appraisalsBlock } from "../../src/blocks/appraisals/manifest.ts";
import { approvalsBlock } from "../../src/blocks/approvals/manifest.ts";
import { assetsBlock } from "../../src/blocks/assets/manifest.ts";
import { attachmentsBlock } from "../../src/blocks/attachments/manifest.ts";
import { bankingBlock } from "../../src/blocks/banking/manifest.ts";
import { billableTimeBlock } from "../../src/blocks/billable-time/manifest.ts";
import { casesBlock } from "../../src/blocks/cases/manifest.ts";
import { commissionsBlock } from "../../src/blocks/commissions/manifest.ts";
import { contactsBlock } from "../../src/blocks/contacts/manifest.ts";
import { contentBlock } from "../../src/blocks/content/manifest.ts";
import { contractsBlock } from "../../src/blocks/contracts/manifest.ts";
import { coursesBlock } from "../../src/blocks/courses/manifest.ts";
import { damBlock } from "../../src/blocks/dam/manifest.ts";
import { deadlinesBlock } from "../../src/blocks/deadlines/manifest.ts";
import { dealsBlock } from "../../src/blocks/deals/manifest.ts";
import { dispatchBlock } from "../../src/blocks/dispatch/manifest.ts";
import { documentTemplatesBlock } from "../../src/blocks/document-templates/manifest.ts";
import { domainsBlock } from "../../src/blocks/domains/manifest.ts";
import { donationsBlock } from "../../src/blocks/donations/manifest.ts";
import { ePrescribingBlock } from "../../src/blocks/e-prescribing/manifest.ts";
import { employeesBlock } from "../../src/blocks/employees/manifest.ts";
import { enrollmentsBlock } from "../../src/blocks/enrollments/manifest.ts";
import { expensesBlock } from "../../src/blocks/expenses/manifest.ts";
import { forecastsBlock } from "../../src/blocks/forecasts/manifest.ts";
import { formsBlock } from "../../src/blocks/forms/manifest.ts";
import { guestsBlock } from "../../src/blocks/guests/manifest.ts";
import { importsBlock } from "../../src/blocks/imports/manifest.ts";
import { incidentsBlock } from "../../src/blocks/incidents/manifest.ts";
import { inspectionsBlock } from "../../src/blocks/inspections/manifest.ts";
import { inventoryBlock } from "../../src/blocks/inventory/manifest.ts";
import { invoicesBlock } from "../../src/blocks/invoices/manifest.ts";
import { leasesBlock } from "../../src/blocks/leases/manifest.ts";
import { leaveBlock } from "../../src/blocks/leave/manifest.ts";
import { legalEntitiesBlock } from "../../src/blocks/legal-entities/manifest.ts";
import { limsBlock } from "../../src/blocks/lims/manifest.ts";
import { mailSyncBlock } from "../../src/blocks/mail-sync/manifest.ts";
import { maintenanceBlock } from "../../src/blocks/maintenance/manifest.ts";
import { manufacturingBlock } from "../../src/blocks/manufacturing/manifest.ts";
import { meetingsBlock } from "../../src/blocks/meetings/manifest.ts";
import { organizationsBlock } from "../../src/blocks/organizations/manifest.ts";
import { passesBlock } from "../../src/blocks/passes/manifest.ts";
import { payrollExportBlock } from "../../src/blocks/payroll-export/manifest.ts";
import { periodsBlock } from "../../src/blocks/periods/manifest.ts";
import { pipelinesBlock } from "../../src/blocks/pipelines/manifest.ts";
import { qualificationsBlock } from "../../src/blocks/qualifications/manifest.ts";
import { quotesBlock } from "../../src/blocks/quotes/manifest.ts";
import { referralsBlock } from "../../src/blocks/referrals/manifest.ts";
import { rfqsBlock } from "../../src/blocks/rfqs/manifest.ts";
import { risksBlock } from "../../src/blocks/risks/manifest.ts";
import { scoresBlock } from "../../src/blocks/scores/manifest.ts";
import { segmentsBlock } from "../../src/blocks/segments/manifest.ts";
import { sequencesBlock } from "../../src/blocks/sequences/manifest.ts";
import { shipmentsBlock } from "../../src/blocks/shipments/manifest.ts";
import { signaturesBlock } from "../../src/blocks/signatures/manifest.ts";
import { templatesBlock } from "../../src/blocks/templates/manifest.ts";
import { tillsBlock } from "../../src/blocks/tills/manifest.ts";
import { versionsBlock } from "../../src/blocks/versions/manifest.ts";
import { warehouseBlock } from "../../src/blocks/warehouse/manifest.ts";
import { warrantyBlock } from "../../src/blocks/warranty/manifest.ts";
import { SQL_MODULES } from "../../src/sql/registry.ts";
import { renderBlocks } from "../../src/sql/render.ts";

// The drive document register renders only with `options.control`; its tests
// render that option.
const BLOCKS = [
  accountingBlock,
  bankingBlock,
  billableTimeBlock,
  expensesBlock,
  invoicesBlock,
  scoresBlock,
  contactsBlock,
  contractsBlock,
  dealsBlock,
  forecastsBlock,
  mailSyncBlock,
  pipelinesBlock,
  quotesBlock,
  segmentsBlock,
  approvalsBlock,
  assetsBlock,
  casesBlock,
  deadlinesBlock,
  documentTemplatesBlock,
  employeesBlock,
  leaveBlock,
  dispatchBlock,
  guestsBlock,
  incidentsBlock,
  accessRequestsBlock,
  agentCheckoutBlock,
  appraisalsBlock,
  commissionsBlock,
  contentBlock,
  coursesBlock,
  damBlock,
  donationsBlock,
  leasesBlock,
  domainsBlock,
  formsBlock,
  importsBlock,
  ePrescribingBlock,
  enrollmentsBlock,
  inspectionsBlock,
  legalEntitiesBlock,
  limsBlock,
  maintenanceBlock,
  manufacturingBlock,
  organizationsBlock,
  periodsBlock,
  referralsBlock,
  passesBlock,
  payrollExportBlock,
  meetingsBlock,
  rfqsBlock,
  risksBlock,
  shipmentsBlock,
  sequencesBlock,
  tillsBlock,
  warehouseBlock,
  warrantyBlock,
  signaturesBlock,
  qualificationsBlock,
  versionsBlock,
  attachmentsBlock,
  templatesBlock,
  inventoryBlock,
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
    expect(CASES).toHaveLength(84);
  });
});
