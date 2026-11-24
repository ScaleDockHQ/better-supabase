/**
 * The thirteen product areas of the sample. Each one groups presets that prove
 * the same flow, and lists the screens a visitor opens to walk it. The area
 * names and steps are product vocabulary, not interface text, so they stay
 * outside the translation catalog. `coverage/block-coverage.ts` maps every
 * preset to one area and `scripts/check-example-coverage.ts` checks every route
 * exists.
 */
export const AREA_IDS = [
  "sales",
  "erp",
  "manufacturing",
  "commerce",
  "service",
  "support",
  "projects",
  "people",
  "content",
  "care",
  "governance",
  "ai",
  "platform",
] as const;

export type AreaId = (typeof AREA_IDS)[number];

export interface AreaStep {
  readonly label: string;
  readonly route: string;
}

export interface Area {
  readonly id: AreaId;
  readonly name: string;
  readonly flow: string;
  readonly steps: readonly AreaStep[];
  /** The Server Actions of the composites this area runs, by action name. */
  readonly actions: readonly string[];
}

export const AREAS: readonly Area[] = [
  {
    id: "sales",
    name: "Sales",
    flow: "Lead to cash",
    steps: [
      { label: "Contacts", route: "/crm/contacts" },
      { label: "Deals", route: "/crm/deals" },
      { label: "Quotes", route: "/crm/quotes" },
      { label: "Contracts", route: "/crm/contracts" },
      { label: "Invoices", route: "/finance/invoices" },
    ],
    actions: ["closeDealLost", "acceptQuote"],
  },
  {
    id: "erp",
    name: "ERP",
    flow: "Order to cash, procure to pay, record to report",
    steps: [
      { label: "Orders", route: "/shop/orders" },
      { label: "Payables", route: "/finance/payables" },
      { label: "RFQs", route: "/rfqs" },
      { label: "Bank", route: "/banking" },
      { label: "Periods", route: "/finance/periods" },
    ],
    actions: ["payAndFulfilOrder", "reconcileAccount"],
  },
  {
    id: "manufacturing",
    name: "Manufacturing and quality",
    flow: "Plan to produce, inspect to corrective action",
    steps: [
      { label: "Plan", route: "/manufacturing" },
      { label: "Production", route: "/production" },
      { label: "Production orders", route: "/manufacturing/orders" },
      { label: "Inspection register", route: "/inspections/register" },
      { label: "Inspections", route: "/inspections" },
      { label: "Risks", route: "/risks" },
      { label: "Qualifications", route: "/qualifications" },
    ],
    actions: [],
  },
  {
    id: "commerce",
    name: "Commerce",
    flow: "Browse to return",
    steps: [
      { label: "Catalog", route: "/shop" },
      { label: "Orders", route: "/shop/orders" },
      { label: "Inventory", route: "/shop/inventory" },
      { label: "Tills", route: "/tills" },
      { label: "Assets", route: "/dam" },
    ],
    actions: [],
  },
  {
    id: "service",
    name: "Service and logistics",
    flow: "Request to completed visit",
    steps: [
      { label: "Dispatch", route: "/field/dispatch" },
      { label: "Day route", route: "/field/day" },
      { label: "Shipments", route: "/field/shipments" },
      { label: "Maintenance", route: "/maintenance" },
      { label: "Warehouse", route: "/warehouse" },
    ],
    actions: [],
  },
  {
    id: "support",
    name: "Support",
    flow: "Conversation to resolution",
    steps: [
      { label: "Inbox", route: "/inbox" },
      { label: "Cases", route: "/cases" },
      { label: "Incidents", route: "/incidents" },
      { label: "Knowledge", route: "/knowledge" },
      { label: "Chat", route: "/chat" },
    ],
    actions: [],
  },
  {
    id: "projects",
    name: "Projects",
    flow: "Project to invoice",
    steps: [
      { label: "Projects", route: "/projects" },
      { label: "Work", route: "/work" },
      { label: "Time", route: "/people/time" },
      { label: "Approvals", route: "/approvals" },
      { label: "Billing", route: "/finance" },
    ],
    actions: ["approveAndInvoiceTimesheet"],
  },
  {
    id: "people",
    name: "People",
    flow: "Hire to retire",
    steps: [
      { label: "Hiring", route: "/people/hiring" },
      { label: "Employees", route: "/people" },
      { label: "Leave", route: "/people/leave" },
      { label: "Courses", route: "/courses" },
      { label: "Payroll", route: "/payroll" },
    ],
    actions: [
      "hireApplication",
      "onboardEmployee",
      "offboardEmployee",
      "assignCourse",
      "bookWithReminder",
    ],
  },
  {
    id: "content",
    name: "Content and files",
    flow: "Draft to published and filed",
    steps: [
      { label: "Content", route: "/content" },
      { label: "Documents", route: "/documents" },
      { label: "Templates", route: "/templates" },
      { label: "Drive", route: "/drive" },
      { label: "Meetings", route: "/meetings" },
    ],
    actions: ["shareDriveWithRoles", "createPublicLink"],
  },
  {
    id: "care",
    name: "Care",
    flow: "Intake to dossier",
    steps: [
      { label: "Clients", route: "/care" },
      { label: "Care plans", route: "/care-plans" },
      { label: "Medications", route: "/medications" },
      { label: "Observations", route: "/observations" },
      { label: "Prescriptions", route: "/prescriptions" },
    ],
    actions: [],
  },
  {
    id: "governance",
    name: "Governance",
    flow: "Risk to control to evidence",
    steps: [
      { label: "Risks", route: "/risks" },
      { label: "Compliance", route: "/compliance" },
      { label: "Advisories", route: "/advisories" },
      { label: "Deadlines", route: "/deadlines" },
      { label: "Audit", route: "/settings/audit" },
    ],
    actions: [],
  },
  {
    id: "ai",
    name: "AI and automation",
    flow: "Prompt to approved action",
    steps: [
      { label: "Assistant", route: "/assistant" },
      { label: "Agents", route: "/assistant/agents" },
      { label: "Runs", route: "/assistant/agents/runs" },
      { label: "Workflows", route: "/workflows" },
      { label: "Rules", route: "/rules" },
    ],
    actions: [],
  },
  {
    id: "platform",
    name: "Platform",
    flow: "Sign-up to paid seat",
    steps: [
      { label: "Members", route: "/settings/members" },
      { label: "Roles", route: "/settings/roles" },
      { label: "API keys", route: "/settings/api-keys" },
      { label: "Webhooks", route: "/settings/webhooks" },
      { label: "Billing", route: "/settings/billing" },
    ],
    actions: [],
  },
];

export const PRESET_AREA = {
  crm: "sales",
  "customer-success": "sales",
  contracts: "sales",
  invoicing: "sales",
  erp: "erp",
  spend: "erp",
  nonprofit: "erp",
  manufacturing: "manufacturing",
  qms: "manufacturing",
  ehs: "manufacturing",
  construction: "manufacturing",
  commerce: "commerce",
  pim: "commerce",
  marketplace: "commerce",
  pos: "commerce",
  fitness: "commerce",
  events: "commerce",
  "field-service": "service",
  logistics: "service",
  property: "service",
  helpdesk: "support",
  itsm: "support",
  claims: "support",
  feedback: "support",
  community: "support",
  chat: "support",
  projects: "projects",
  psa: "projects",
  people: "people",
  ats: "people",
  lms: "people",
  scheduling: "people",
  cms: "content",
  docs: "content",
  drive: "content",
  intranet: "content",
  forms: "content",
  legal: "content",
  filings: "content",
  clinic: "care",
  care: "care",
  compliance: "governance",
  isms: "governance",
  enterprise: "governance",
  admin: "governance",
  ai: "ai",
  "ai-chat": "ai",
  "ai-agents": "ai",
  automation: "ai",
  minimal: "platform",
  saas: "platform",
  consumer: "platform",
  "developer-api": "platform",
  everything: "platform",
} as const satisfies Readonly<Record<string, AreaId>>;
