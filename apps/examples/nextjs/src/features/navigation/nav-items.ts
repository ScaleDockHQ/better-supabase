import type { Permission } from "@/features/user/user-permissions";
import type { navFlags } from "@/flags";
import type { AppHref } from "@/i18n/navigation";

export type NavId =
  | "dashboard"
  | "myWork"
  | "customers"
  | "people"
  | "hiring"
  | "leave"
  | "onboarding"
  | "deadlines"
  | "documentTemplates"
  | "time"
  | "calendar"
  | "availability"
  | "work"
  | "workGrid"
  | "projects"
  | "approvals"
  | "rules"
  | "contacts"
  | "deals"
  | "sequences"
  | "quotes"
  | "salesHome"
  | "pipelines"
  | "forecasts"
  | "segments"
  | "queues"
  | "scoring"
  | "contracts"
  | "commissions"
  | "referrals"
  | "customerSuccess"
  | "shop"
  | "inventory"
  | "manufacturing"
  | "production"
  | "banking"
  | "legalEntities"
  | "payrollExport"
  | "orders"
  | "dispatch"
  | "myDay"
  | "shipments"
  | "drive"
  | "documents"
  | "forms"
  | "courses"
  | "community"
  | "templates"
  | "imports"
  | "trash"
  | "metrics"
  | "compliance"
  | "qualifications"
  | "risks"
  | "cases"
  | "inspections"
  | "meetings"
  | "maintenance"
  | "dam"
  | "lims"
  | "appraisals"
  | "warehouse"
  | "rfqs"
  | "donations"
  | "passes"
  | "reviews"
  | "warranty"
  | "leases"
  | "assets"
  | "tills"
  | "shifts"
  | "finance"
  | "payables"
  | "care"
  | "observations"
  | "medications"
  | "careAlerts"
  | "prescriptions"
  | "carePlans"
  | "funding"
  | "notifications"
  | "workflows"
  | "workflowRuns"
  | "inbox"
  | "chat"
  | "assistant"
  | "knowledge"
  | "agentActivity"
  | "agents"
  | "prompts"
  | "evals"
  | "guardrails"
  | "aiUsage"
  | "aiTasks"
  | "beta"
  | "islands"
  | "members"
  | "teams"
  | "roles"
  | "billing"
  | "apiKeys"
  | "audit"
  | "aiProviders"
  | "settings";

/** The product areas of the side navigation, in the order they render. */
export const navAreas = [
  "home",
  "sales",
  "commerce",
  "operations",
  "finance",
  "people",
  "work",
  "content",
  "quality",
  "care",
  "ai",
  "admin",
] as const;

export type NavArea = (typeof navAreas)[number];

export interface NavItem {
  readonly id: NavId;
  /** Without the locale prefix. */
  readonly href: AppHref;
  readonly area: NavArea;
  /**
   * Hidden from the menu without it, and the proxy answers the page with a 403
   * when the token's `permissions` claim lacks it.
   */
  readonly requires?: Permission;
  /** Shown only while this flag is on for the organization. */
  readonly flag?: keyof typeof navFlags;
}

export const navItems: readonly NavItem[] = [
  { id: "dashboard", href: "/", area: "home" },
  { id: "myWork", href: "/my-work", area: "home" },
  {
    id: "customers",
    href: "/customers",
    area: "sales",
    requires: "customers.read",
  },
  { id: "work", href: "/work", area: "work", requires: "tasks.read" },
  { id: "workGrid", href: "/work/grid", area: "work", requires: "tasks.read" },
  { id: "projects", href: "/projects", area: "work" },
  {
    id: "approvals",
    href: "/approvals",
    area: "work",
    requires: "approvals.read",
  },
  { id: "rules", href: "/rules", area: "work", requires: "automations.read" },
  { id: "people", href: "/people", area: "people", requires: "employees.read" },
  {
    id: "hiring",
    href: "/people/hiring",
    area: "people",
    requires: "hiring.read",
  },
  {
    id: "leave",
    href: "/people/leave",
    area: "people",
    requires: "leave.request",
  },
  {
    id: "onboarding",
    href: "/people/onboarding",
    area: "people",
    requires: "enrollments.read",
  },
  {
    id: "deadlines",
    href: "/deadlines",
    area: "work",
    requires: "deadlines.read",
  },
  {
    id: "documentTemplates",
    href: "/documents/templates",
    area: "content",
    requires: "document_templates.read",
  },
  {
    id: "time",
    href: "/people/time",
    area: "people",
    requires: "time_entries.track",
  },
  {
    id: "calendar",
    href: "/calendar",
    area: "work",
    requires: "calendar.read",
  },
  {
    id: "availability",
    href: "/calendar/availability",
    area: "work",
    requires: "bookings.manage",
  },
  {
    id: "contacts",
    href: "/crm/contacts",
    area: "sales",
    requires: "contacts.read",
  },
  { id: "deals", href: "/crm/deals", area: "sales", requires: "deals.read" },
  {
    id: "sequences",
    href: "/crm/sequences",
    area: "sales",
    requires: "sequences.read",
  },
  { id: "quotes", href: "/crm/quotes", area: "sales", requires: "quotes.read" },
  { id: "salesHome", href: "/crm", area: "sales", requires: "deals.read" },
  {
    id: "pipelines",
    href: "/crm/pipelines",
    area: "sales",
    requires: "pipelines.read",
  },
  {
    id: "forecasts",
    href: "/crm/forecasts",
    area: "sales",
    requires: "forecasts.read",
  },
  {
    id: "segments",
    href: "/crm/segments",
    area: "sales",
    requires: "segments.read",
  },
  {
    id: "queues",
    href: "/crm/queues",
    area: "sales",
    requires: "assignment.read",
  },
  {
    id: "scoring",
    href: "/crm/scoring",
    area: "sales",
    requires: "scores.read",
  },
  {
    id: "contracts",
    href: "/crm/contracts",
    area: "sales",
    requires: "contracts.read",
  },
  {
    id: "commissions",
    href: "/crm/commissions",
    area: "sales",
    requires: "commissions.read",
  },
  {
    id: "referrals",
    href: "/crm/referrals",
    area: "sales",
    requires: "referrals.read",
  },
  {
    id: "customerSuccess",
    href: "/crm/success",
    area: "sales",
    requires: "scores.read",
  },
  { id: "shop", href: "/shop", area: "commerce", requires: "catalog.read" },
  {
    id: "inventory",
    href: "/shop/inventory",
    area: "commerce",
    requires: "inventory.read",
  },
  {
    id: "manufacturing",
    href: "/manufacturing",
    area: "operations",
    requires: "manufacturing.read",
  },
  {
    id: "production",
    href: "/production",
    area: "operations",
    requires: "manufacturing.read",
  },
  {
    id: "banking",
    href: "/banking",
    area: "finance",
    requires: "banking.read",
  },
  {
    id: "legalEntities",
    href: "/legal-entities",
    area: "finance",
    requires: "legal_entities.read",
  },
  {
    id: "payrollExport",
    href: "/payroll",
    area: "finance",
    requires: "payroll_export.read",
  },
  {
    id: "orders",
    href: "/shop/orders",
    area: "commerce",
    requires: "orders.read",
  },
  {
    id: "dispatch",
    href: "/field/dispatch",
    area: "operations",
    requires: "dispatch.read",
  },
  {
    id: "myDay",
    href: "/field/day",
    area: "operations",
    requires: "dispatch.work",
  },
  {
    id: "shipments",
    href: "/field/shipments",
    area: "operations",
    requires: "shipments.read",
  },
  { id: "drive", href: "/drive", area: "content", requires: "drive.read" },
  {
    id: "documents",
    href: "/documents",
    area: "content",
    requires: "documents.read",
  },
  { id: "forms", href: "/forms", area: "content", requires: "forms.read" },
  { id: "courses", href: "/courses", area: "people", requires: "courses.read" },
  {
    id: "community",
    href: "/community",
    area: "content",
    requires: "posts.read",
  },
  {
    id: "templates",
    href: "/templates",
    area: "content",
    requires: "templates.read",
  },
  { id: "imports", href: "/imports", area: "work", requires: "imports.manage" },
  { id: "trash", href: "/trash", area: "content", requires: "trash.read" },
  { id: "metrics", href: "/metrics", area: "quality" },
  {
    id: "compliance",
    href: "/compliance",
    area: "quality",
    requires: "compliance.read",
  },
  { id: "qualifications", href: "/qualifications", area: "people" },
  { id: "risks", href: "/risks", area: "quality", requires: "risks.read" },
  { id: "cases", href: "/cases", area: "quality", requires: "cases.read" },
  {
    id: "inspections",
    href: "/inspections",
    area: "quality",
    requires: "inspections.read",
  },
  {
    id: "meetings",
    href: "/meetings",
    area: "work",
    requires: "meetings.read",
  },
  { id: "dam", href: "/dam", area: "operations", requires: "dam.read" },
  { id: "lims", href: "/lims", area: "operations", requires: "lims.read" },
  { id: "rfqs", href: "/rfqs", area: "operations", requires: "rfqs.read" },
  {
    id: "donations",
    href: "/shop/donations",
    area: "commerce",
    requires: "donations.read",
  },
  {
    id: "warranty",
    href: "/shop/warranty",
    area: "commerce",
    requires: "warranty.read",
  },
  {
    id: "reviews",
    href: "/shop/reviews",
    area: "commerce",
    requires: "reviews.manage",
  },
  {
    id: "passes",
    href: "/shop/passes",
    area: "commerce",
    requires: "passes.read",
  },
  {
    id: "leases",
    href: "/property/leases",
    area: "operations",
    requires: "leases.read",
  },
  {
    id: "assets",
    href: "/assets",
    area: "operations",
    requires: "assets.read",
  },
  { id: "tills", href: "/tills", area: "commerce", requires: "tills.read" },
  {
    id: "maintenance",
    href: "/maintenance",
    area: "operations",
    requires: "maintenance.read",
  },
  {
    id: "appraisals",
    href: "/appraisals",
    area: "people",
    requires: "appraisals.review",
  },
  {
    id: "warehouse",
    href: "/warehouse",
    area: "operations",
    requires: "warehouse.pick",
  },
  { id: "shifts", href: "/shifts", area: "people" },
  {
    id: "finance",
    href: "/finance",
    area: "finance",
    requires: "accounting.read",
  },
  {
    id: "payables",
    href: "/finance/payables",
    area: "finance",
    requires: "invoices.read",
  },
  { id: "care", href: "/care", area: "care", requires: "customers.read" },
  {
    id: "observations",
    href: "/observations",
    area: "care",
    requires: "observations.read",
  },
  {
    id: "medications",
    href: "/medications",
    area: "care",
    requires: "medications.read",
  },
  {
    id: "careAlerts",
    href: "/care-alerts",
    area: "care",
    requires: "clinical_decision_support.read",
  },
  {
    id: "prescriptions",
    href: "/prescriptions",
    area: "care",
    requires: "e_prescribing.read",
  },
  {
    id: "carePlans",
    href: "/care-plans",
    area: "care",
    requires: "care_plans.read",
  },
  {
    id: "funding",
    href: "/funding",
    area: "finance",
    requires: "funding.read",
  },
  { id: "notifications", href: "/notifications", area: "home" },
  {
    id: "workflows",
    href: "/workflows",
    area: "ai",
    requires: "workflows.read",
  },
  {
    id: "workflowRuns",
    href: "/workflows/runs",
    area: "ai",
    requires: "workflows.read",
  },
  { id: "inbox", href: "/inbox", area: "work", requires: "inbox.read" },
  { id: "chat", href: "/chat", area: "work", requires: "messages.read" },
  {
    id: "assistant",
    href: "/assistant",
    area: "ai",
    requires: "ai_chat.create",
  },
  {
    id: "knowledge",
    href: "/knowledge",
    area: "ai",
    requires: "knowledge.write",
  },
  {
    id: "agentActivity",
    href: "/assistant/activity",
    area: "ai",
    requires: "ai_chat.create",
  },
  {
    id: "agents",
    href: "/assistant/agents",
    area: "ai",
    requires: "agents.read",
  },
  {
    id: "prompts",
    href: "/assistant/prompts",
    area: "ai",
    requires: "ai_chat.manage",
  },
  {
    id: "evals",
    href: "/assistant/evals",
    area: "ai",
    requires: "ai_chat.manage",
  },
  {
    id: "guardrails",
    href: "/assistant/guardrails",
    area: "ai",
    requires: "ai_chat.manage",
  },
  {
    id: "aiUsage",
    href: "/assistant/usage",
    area: "ai",
    requires: "ai_chat.read",
  },
  {
    id: "aiTasks",
    href: "/assistant/tasks",
    area: "ai",
    requires: "ai_schedules.write",
  },
  { id: "beta", href: "/beta", area: "admin", flag: "beta-page" },
  { id: "islands", href: "/islands", area: "admin" },
  {
    id: "members",
    href: "/settings/members",
    area: "admin",
    requires: "members.read",
  },
  {
    id: "teams",
    href: "/settings/teams",
    area: "admin",
    requires: "teams.read",
  },
  {
    id: "roles",
    href: "/settings/roles",
    area: "admin",
    requires: "members.read",
  },
  {
    id: "billing",
    href: "/settings/billing",
    area: "admin",
    requires: "billing.read",
  },
  {
    id: "apiKeys",
    href: "/settings/api-keys",
    area: "admin",
    requires: "api_keys.own",
  },
  {
    id: "audit",
    href: "/settings/audit",
    area: "admin",
    requires: "audit.read",
  },
  {
    id: "aiProviders",
    href: "/settings/ai-providers",
    area: "admin",
    requires: "ai_keys.manage",
  },
  {
    id: "settings",
    href: "/settings/organization",
    area: "admin",
    requires: "settings.read",
  },
];

/** The permission a path (without the locale) needs, from its menu entry. */
export function requiredPermission(pathname: string): Permission | undefined {
  const id = activeNavId(pathname);

  return navItems.find((item) => item.id === id)?.requires;
}

/** The menu entry a path belongs to, for `aria-current`. */
export function activeNavId(pathname: string): NavId | undefined {
  return navItems
    .filter(
      (item) =>
        pathname === item.href ||
        (item.href !== "/" && pathname.startsWith(`${item.href}/`)),
    )
    .toSorted((a, b) => b.href.length - a.href.length)[0]?.id;
}
