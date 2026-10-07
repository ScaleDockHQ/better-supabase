import type { Permission } from "@/features/user/user-permissions";

export type SettingsTabId =
  | "profile"
  | "security"
  | "organization"
  | "members"
  | "billing"
  | "apiKeys"
  | "audit";

export interface SettingsTab {
  readonly id: SettingsTabId;
  readonly href: string;
  readonly requires?: Permission;
}

/** The proxy reads the same permissions from `navItems` for the organization tabs. */
export const settingsTabs: readonly SettingsTab[] = [
  { id: "profile", href: "/settings/profile" },
  { id: "security", href: "/settings/security" },
  {
    id: "organization",
    href: "/settings/organization",
    requires: "settings.read",
  },
  { id: "members", href: "/settings/members", requires: "members.read" },
  { id: "billing", href: "/settings/billing", requires: "billing.read" },
  { id: "apiKeys", href: "/settings/api-keys", requires: "api_keys.own" },
  { id: "audit", href: "/settings/audit", requires: "audit.read" },
];
