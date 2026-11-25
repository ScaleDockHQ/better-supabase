/**
 * The Server Actions `actions.spec.ts` calls, with the page they belong to and
 * the arguments of one call. An action of the build that is not listed here
 * counts as uncovered in `perf/report.json`. `mutates` marks a write, which the
 * spec runs after the reads so a write cannot change what a read measures.
 */

import { firstRowId } from "./support/seed-lookup";

export interface ActionCase {
  /** The action file under src/, for instance `features/inbox/inbox-actions.ts`. */
  readonly file: string;
  readonly name: string;
  /** The page whose UI calls the action. */
  readonly page: string;
  readonly args: readonly unknown[];
  /** Builds the arguments from the seeded rows when the action takes ids. */
  readonly resolve?: () => Promise<readonly unknown[]>;
  readonly mutates: boolean;
}

const read = (
  file: string,
  name: string,
  page: string,
  args: readonly unknown[] = [],
): ActionCase => ({ file, name, page, args, mutates: false });

const write = (
  file: string,
  name: string,
  page: string,
  resolve: () => Promise<readonly unknown[]>,
): ActionCase => ({ file, name, page, args: [], resolve, mutates: true });

/**
 * An id no row holds, for the writes that would change a seeded story (closing
 * the period, releasing or completing an order, closing an inspection): the
 * call still reaches the action and measures it, and the story stays as
 * seeded.
 */
const MISSING_ID = "00000000-0000-4000-8000-00000000dead";

const SALES = "features/sales/sales-actions.ts";

const CARE_PLANS = "features/care-plans/care-plans-actions.ts";

const E_PRESCRIBING = "features/e-prescribing/e-prescribing-actions.ts";

const COMPOSITES = "features/composites/composites-actions.ts";

const AGENTS = "features/agents/agents-actions.ts";

const WEBHOOKS = "features/webhooks/webhooks-actions.ts";

const MANUFACTURING = "features/manufacturing/manufacturing-actions.ts";

const INSPECTIONS = "features/inspections/inspections-actions.ts";

export const ACTIONS: readonly ActionCase[] = [
  read(
    "features/organization/organization-actions.ts",
    "loadMyOrganizations",
    "/",
  ),
  read(
    "features/organization/organization-actions.ts",
    "loadMembers",
    "/settings/members",
  ),
  read(
    "features/billing/billing-actions.ts",
    "loadPlanCatalog",
    "/settings/billing",
  ),
  read("features/inbox/inbox-actions.ts", "loadInboxes", "/inbox"),
  read("features/inbox/inbox-actions.ts", "loadTeams", "/inbox"),
  read("features/inbox/inbox-actions.ts", "loadMacros", "/inbox"),
  read("features/inbox/inbox-actions.ts", "loadDrafts", "/inbox"),
  read("features/inbox/inbox-actions.ts", "loadScheduled", "/inbox"),
  read("features/inbox/inbox-actions.ts", "loadInboundEvents", "/inbox"),
  read("features/inbox/inbox-actions.ts", "loadConversations", "/inbox"),
  read(
    "features/knowledge/knowledge-actions.ts",
    "searchKnowledge",
    "/knowledge",
    [{ query: "refund" }],
  ),
  write(SALES, "addObligation", "/crm/contracts", async () => [
    {
      contractId: await firstRowId("contracts"),
      title: "Send the renewal quote",
    },
  ]),
  write(SALES, "refreshSegment", "/crm/segments", async () => [
    { segmentId: await firstRowId("segments") },
  ]),
  write(COMPOSITES, "closeDealLost", "/crm/deals", async () => [
    { dealId: await firstRowId("deals"), withdraw: [] },
  ]),
  write(COMPOSITES, "acceptQuote", "/crm/quotes", async () => [
    { quoteId: await firstRowId("quotes") },
  ]),
  write(COMPOSITES, "payAndFulfilOrder", "/shop/orders", async () => [
    { orderId: await firstRowId("orders") },
  ]),
  write(COMPOSITES, "prescribeMedicationWithConsent", "/care", async () => [
    {
      clientId: await firstRowId("customers"),
      medicationId: await firstRowId("medications"),
      purposeKey: "medication",
      dose: "500",
      times: "08:00",
    },
  ]),
  write(CARE_PLANS, "publishCarePlan", "/care-plans", async () => [
    { planId: await firstRowId("care_plans") },
  ]),
  write(CARE_PLANS, "archiveCarePlan", "/care-plans", async () => [
    { planId: await firstRowId("care_plans") },
  ]),
  write(E_PRESCRIBING, "signPrescription", "/prescriptions", async () => [
    { prescriptionId: await firstRowId("prescriptions") },
  ]),
  write(E_PRESCRIBING, "cancelPrescription", "/prescriptions", async () => [
    { prescriptionId: await firstRowId("prescriptions") },
  ]),
  write(COMPOSITES, "exportRecordSubject", "/risks", async () => [
    { subjectType: "risk", subjectId: await firstRowId("risks") },
  ]),
  write(
    COMPOSITES,
    "approveAndInvoiceTimesheet",
    "/projects/portfolio",
    async () => [{ timesheetId: MISSING_ID }],
  ),
  write(COMPOSITES, "shareDriveWithRoles", "/drive", async () => [
    { id: MISSING_ID, roles: ["member"], role: "viewer" },
  ]),
  write(COMPOSITES, "createPublicLink", "/drive", async () => [
    { id: MISSING_ID, days: 7 },
  ]),
  write(COMPOSITES, "reconcileAccount", "/banking/accounts", async () => [
    { accountId: await firstRowId("bank_accounts") },
  ]),
  write(COMPOSITES, "rotateKey", "/settings/api-keys", async () => [
    { id: await firstRowId("api_keys"), graceHours: 24 },
  ]),
  write(COMPOSITES, "inviteWithinSeats", "/settings/members", async () => [
    { email: "seat-check@acme.test", role: "member" },
  ]),
  write(AGENTS, "decideApprovals", "/assistant/agents", async () => [
    {
      decisions: [
        {
          chatId: "00000000-0000-4000-8000-00000a9c0001",
          approvalId: "areas-12-13-approval-1",
        },
      ],
      approved: true,
    },
  ]),
  write(AGENTS, "decideApproval", "/assistant/agents", async () => [
    { approvalId: "areas-12-13-approval-missing", approved: true },
  ]),
  write(WEBHOOKS, "redeliverWebhook", "/settings/webhooks", async () => [
    { id: await firstRowId("webhook_deliveries") },
  ]),
  // Service and logistics
  write(COMPOSITES, "completeVisit", "/field/dispatch", async () => [
    { workOrderId: await firstRowId("work_orders") },
  ]),
  // Support
  write(COMPOSITES, "openTicket", "/cases", async () => [
    { title: "Printer on the second floor is offline" },
  ]),
  write(COMPOSITES, "discussCase", "/cases", async () => [
    { caseId: await firstRowId("cases"), comment: "Looking into the cause." },
  ]),
  // People
  write(COMPOSITES, "hireApplication", "/people/hiring", async () => [
    { applicationId: await firstRowId("applications") },
  ]),
  write(COMPOSITES, "onboardEmployee", "/people", async () => [
    { name: "Noor Jansen", program: "new-hire" },
  ]),
  write(COMPOSITES, "offboardEmployee", "/people", async () => [
    {
      employeeId: "00000000-0000-4000-8000-0000000e0005",
      endDate: "2030-01-31",
    },
  ]),
  write(COMPOSITES, "assignCourse", "/courses", async () => [
    {
      courseId: await firstRowId("courses"),
      userId: "00000000-0000-4000-8000-0000000000a2",
    },
  ]),
  write(COMPOSITES, "bookWithReminder", "/people", async () => [
    { name: "Priya Patel", date: "2030-01-15", hour: "10" },
  ]),
  write(
    "features/onboarding/onboarding-actions.ts",
    "completeOnboardingStep",
    "/people/onboarding",
    async () => [
      { enrollmentId: await firstRowId("enrollments"), step: "accounts" },
    ],
  ),
  write(COMPOSITES, "closeAccountingPeriod", "/finance/periods", async () => [
    { periodId: MISSING_ID },
  ]),
  write(
    "features/compliance/compliance-actions.ts",
    "addControlEvidence",
    "/compliance/controls/[id]",
    async () => [{ controlId: MISSING_ID, note: "Access review evidence" }],
  ),
  write(
    "features/dunning/dunning-actions.ts",
    "applyStandardDunningLevels",
    "/finance/invoices",
    async () => [{}],
  ),
  write(COMPOSITES, "payDueBills", "/finance/payables", async () => [
    {
      accountId: await firstRowId("bank_accounts"),
      dueBy: "2000-01-01",
      creditorName: "Supplier",
      creditorIban: "NL91ABNA0417164300",
    },
  ]),
  write(COMPOSITES, "requestOrderReturn", "/shop/orders", async () => [
    { orderId: await firstRowId("orders") },
  ]),
  write(COMPOSITES, "settleReturn", "/shop/orders", async () => [
    {
      returnId: await firstRowId("order_returns"),
      disposition: "restock",
      refund: false,
    },
  ]),
  write(
    MANUFACTURING,
    "releaseProductionOrder",
    "/manufacturing/orders",
    async () => [{ orderId: MISSING_ID }],
  ),
  write(
    MANUFACTURING,
    "completeProductionOrder",
    "/manufacturing/orders",
    async () => [{ orderId: MISSING_ID, produced: 1 }],
  ),
  write(INSPECTIONS, "raiseFindingCase", "/inspections/register", async () => [
    { findingId: MISSING_ID },
  ]),
  write(INSPECTIONS, "closeInspection", "/inspections/register", async () => [
    { inspectionId: MISSING_ID },
  ]),
  write(
    "features/shop/shop-actions.ts",
    "setProductStatus",
    "/shop",
    async () => [{ productId: await firstRowId("products"), status: "active" }],
  ),
];
