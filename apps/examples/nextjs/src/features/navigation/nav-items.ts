import type { Permission } from "@/features/user/user-permissions";
import type { navFlags } from "@/flags";
import type { AppHref } from "@/i18n/navigation";

export type NavId =
  | "dashboard"
  | "myWork"
  | "customers"
  | "people"
  | "hiring"
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
  | "shop"
  | "inventory"
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
  | "notifications"
  | "workflows"
  | "workflowBuilder"
  | "inbox"
  | "chat"
  | "assistant"
  | "knowledge"
  | "agentActivity"
  | "aiTasks"
  | "beta"
  | "members"
  | "teams"
  | "roles"
  | "billing"
  | "apiKeys"
  | "audit"
  | "aiProviders"
  | "settings";

export interface NavItem {
  readonly id: NavId;
  /** Without the locale prefix. */
  readonly href: AppHref;
  readonly group: "workspace" | "organization";
  /**
   * Hidden from the menu without it, and the proxy answers the page with a 403
   * when the token's `permissions` claim lacks it.
   */
  readonly requires?: Permission;
  /** Shown only while this flag is on for the organization. */
  readonly flag?: keyof typeof navFlags;
}

export const navItems: readonly NavItem[] = [
  { id: "dashboard", href: "/", group: "workspace" },
  { id: "myWork", href: "/my-work", group: "workspace" },
  {
    id: "customers",
    href: "/customers",
    group: "workspace",
    requires: "customers.read",
  },
  {
    id: "work",
    href: "/work",
    group: "workspace",
    requires: "work_items.read",
  },
  {
    id: "workGrid",
    href: "/work/grid",
    group: "workspace",
    requires: "work_items.read",
  },
  { id: "projects", href: "/projects", group: "workspace" },
  {
    id: "approvals",
    href: "/approvals",
    group: "workspace",
    requires: "approvals.read",
  },
  { id: "rules", href: "/rules", group: "workspace", requires: "rules.read" },
  {
    id: "people",
    href: "/people",
    group: "workspace",
    requires: "employees.read",
  },
  {
    id: "hiring",
    href: "/people/hiring",
    group: "workspace",
    requires: "hiring.read",
  },
  {
    id: "time",
    href: "/people/time",
    group: "workspace",
    requires: "time_tracking.track",
  },
  {
    id: "calendar",
    href: "/calendar",
    group: "workspace",
    requires: "calendar.read",
  },
  {
    id: "availability",
    href: "/calendar/availability",
    group: "workspace",
    requires: "bookings.manage",
  },
  {
    id: "contacts",
    href: "/crm/contacts",
    group: "workspace",
    requires: "parties.read",
  },
  {
    id: "deals",
    href: "/crm/deals",
    group: "workspace",
    requires: "deals.read",
  },
  {
    id: "sequences",
    href: "/crm/sequences",
    group: "workspace",
    requires: "sequences.read",
  },
  {
    id: "quotes",
    href: "/crm/quotes",
    group: "workspace",
    requires: "quotes.read",
  },
  { id: "shop", href: "/shop", group: "workspace", requires: "catalog.read" },
  {
    id: "inventory",
    href: "/shop/inventory",
    group: "workspace",
    requires: "inventory.read",
  },
  {
    id: "orders",
    href: "/shop/orders",
    group: "workspace",
    requires: "orders.read",
  },
  {
    id: "dispatch",
    href: "/field/dispatch",
    group: "workspace",
    requires: "dispatch.read",
  },
  {
    id: "myDay",
    href: "/field/day",
    group: "workspace",
    requires: "dispatch.work",
  },
  {
    id: "shipments",
    href: "/field/shipments",
    group: "workspace",
    requires: "shipments.read",
  },
  { id: "drive", href: "/drive", group: "workspace", requires: "drive.read" },
  {
    id: "documents",
    href: "/documents",
    group: "workspace",
    requires: "documents.read",
  },
  { id: "forms", href: "/forms", group: "workspace", requires: "forms.read" },
  {
    id: "courses",
    href: "/courses",
    group: "workspace",
    requires: "courses.read",
  },
  {
    id: "community",
    href: "/community",
    group: "workspace",
    requires: "posts.read",
  },
  {
    id: "templates",
    href: "/templates",
    group: "workspace",
    requires: "templates.read",
  },
  {
    id: "imports",
    href: "/imports",
    group: "workspace",
    requires: "imports.manage",
  },
  { id: "trash", href: "/trash", group: "workspace", requires: "trash.read" },
  { id: "metrics", href: "/metrics", group: "workspace" },
  {
    id: "compliance",
    href: "/compliance",
    group: "workspace",
    requires: "controls.read",
  },
  { id: "notifications", href: "/notifications", group: "workspace" },
  {
    id: "workflows",
    href: "/workflows",
    group: "workspace",
    requires: "workflow.read",
  },
  {
    id: "workflowBuilder",
    href: "/workflows/builder",
    group: "workspace",
    requires: "workflow.read",
  },
  { id: "inbox", href: "/inbox", group: "workspace", requires: "inbox.read" },
  { id: "chat", href: "/chat", group: "workspace", requires: "messages.read" },
  {
    id: "assistant",
    href: "/assistant",
    group: "workspace",
    requires: "ai_chat.create",
  },
  {
    id: "knowledge",
    href: "/knowledge",
    group: "workspace",
    requires: "ai.create",
  },
  {
    id: "agentActivity",
    href: "/assistant/activity",
    group: "workspace",
    requires: "ai_chat.create",
  },
  {
    id: "aiTasks",
    href: "/assistant/tasks",
    group: "workspace",
    requires: "ai.create",
  },
  { id: "beta", href: "/beta", group: "workspace", flag: "beta-page" },
  {
    id: "members",
    href: "/settings/members",
    group: "organization",
    requires: "members.read",
  },
  {
    id: "teams",
    href: "/settings/teams",
    group: "organization",
    requires: "teams.read",
  },
  {
    id: "roles",
    href: "/settings/roles",
    group: "organization",
    requires: "members.read",
  },
  {
    id: "billing",
    href: "/settings/billing",
    group: "organization",
    requires: "billing.read",
  },
  {
    id: "apiKeys",
    href: "/settings/api-keys",
    group: "organization",
    requires: "api_keys.own",
  },
  {
    id: "audit",
    href: "/settings/audit",
    group: "organization",
    requires: "audit.read",
  },
  {
    id: "aiProviders",
    href: "/settings/ai-providers",
    group: "organization",
    requires: "ai.admin",
  },
  {
    id: "settings",
    href: "/settings/organization",
    group: "organization",
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
