import type { Permission } from "@/features/user/user-permissions";
import type { AppHref } from "@/i18n/navigation";

export type SettingsTabId =
  | "profile"
  | "preferences"
  | "security"
  | "privacy"
  | "organization"
  | "members"
  | "accessRequests"
  | "billing"
  | "apiKeys"
  | "webhooks"
  | "signingKeys"
  | "sso"
  | "customFields"
  | "jobs"
  | "audit"
  | "aiProviders";

export interface SettingsTab {
  readonly id: SettingsTabId;
  readonly href: AppHref;
  readonly requires?: Permission;
}

/**
 * The proxy reads the same permissions from `navItems` for the organization
 * tabs.
 */
export const settingsTabs: readonly SettingsTab[] = [
  { id: "profile", href: "/settings/profile" },
  { id: "preferences", href: "/settings/preferences" },
  { id: "security", href: "/settings/security" },
  { id: "privacy", href: "/settings/privacy" },
  {
    id: "organization",
    href: "/settings/organization",
    requires: "settings.read",
  },
  { id: "members", href: "/settings/members", requires: "members.read" },
  {
    id: "accessRequests",
    href: "/settings/access-requests",
    requires: "access_requests.create",
  },
  { id: "billing", href: "/settings/billing", requires: "billing.read" },
  { id: "apiKeys", href: "/settings/api-keys", requires: "api_keys.own" },
  { id: "webhooks", href: "/settings/webhooks", requires: "webhooks.read" },
  {
    id: "signingKeys",
    href: "/settings/signing-keys",
    requires: "organization.update",
  },
  { id: "sso", href: "/settings/sso", requires: "sso.manage" },
  {
    id: "customFields",
    href: "/settings/custom-fields",
    requires: "custom_fields.read",
  },
  { id: "jobs", href: "/settings/jobs", requires: "audit.read" },
  { id: "audit", href: "/settings/audit", requires: "audit.read" },
  { id: "aiProviders", href: "/settings/ai-providers", requires: "ai.admin" },
];
