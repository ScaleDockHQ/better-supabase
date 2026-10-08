import type { Permission } from "@/features/user/user-permissions";

export type NavId =
  | "dashboard"
  | "customers"
  | "notifications"
  | "workflows"
  | "workflowBuilder"
  | "inbox"
  | "beta"
  | "members"
  | "billing"
  | "apiKeys"
  | "audit"
  | "settings";

export interface NavItem {
  readonly id: NavId;
  /** Without the locale prefix. */
  readonly href: string;
  readonly group: "workspace" | "organization";
  /** Hidden from the menu (and redirected by the proxy) without it. */
  readonly requires?: Permission;
  /** Shown only while this flag is on for the organization. */
  readonly flag?: string;
}

export const navItems: readonly NavItem[] = [
  { id: "dashboard", href: "/", group: "workspace" },
  {
    id: "customers",
    href: "/customers",
    group: "workspace",
    requires: "customers.read",
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
  { id: "beta", href: "/beta", group: "workspace", flag: "beta-page" },
  {
    id: "members",
    href: "/settings/members",
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
    id: "settings",
    href: "/settings/organization",
    group: "organization",
    requires: "settings.read",
  },
];

/** The permission a path (without the locale) needs, from its menu entry. */
export function requiredPermission(pathname: string): Permission | undefined {
  return navItems.find(
    (item) =>
      item.href !== "/" &&
      (pathname === item.href || pathname.startsWith(`${item.href}/`)),
  )?.requires;
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
