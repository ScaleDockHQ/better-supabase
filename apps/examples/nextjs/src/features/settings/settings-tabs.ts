import type { Permission } from "@/features/user/user-permissions";
import type { AppHref } from "@/i18n/navigation";

export type SettingsTabId =
  | "profile"
  | "preferences"
  | "integrations"
  | "security"
  | "privacy"
  | "organization"
  | "members"
  | "teams"
  | "roles"
  | "accessRequests"
  | "billing"
  | "apiKeys"
  | "webhooks"
  | "incomingWebhooks"
  | "domains"
  | "optionSets"
  | "flags"
  | "numbering"
  | "securityEvents"
  | "oauthApps"
  | "searchSettings"
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
  { id: "integrations", href: "/settings/integrations" },
  { id: "security", href: "/settings/security" },
  { id: "privacy", href: "/settings/privacy" },
  {
    id: "organization",
    href: "/settings/organization",
    requires: "settings.read",
  },
  { id: "members", href: "/settings/members", requires: "members.read" },
  { id: "teams", href: "/settings/teams", requires: "teams.read" },
  { id: "roles", href: "/settings/roles", requires: "members.read" },
  {
    id: "accessRequests",
    href: "/settings/access-requests",
    requires: "access_requests.create",
  },
  { id: "billing", href: "/settings/billing", requires: "billing.read" },
  { id: "apiKeys", href: "/settings/api-keys", requires: "api_keys.own" },
  { id: "webhooks", href: "/settings/webhooks", requires: "webhooks.read" },
  {
    id: "incomingWebhooks",
    href: "/settings/webhooks/incoming",
    requires: "webhooks.read",
  },
  { id: "domains", href: "/settings/domains", requires: "domains.read" },
  {
    id: "optionSets",
    href: "/settings/option-sets",
    requires: "option_sets.read",
  },
  { id: "flags", href: "/settings/flags", requires: "flags.manage" },
  {
    id: "numbering",
    href: "/settings/numbering",
    requires: "numbering.assign",
  },
  {
    id: "securityEvents",
    href: "/settings/security/events",
    requires: "audit.read",
  },
  {
    id: "oauthApps",
    href: "/settings/oauth-apps",
    requires: "settings.manage",
  },
  { id: "searchSettings", href: "/settings/search", requires: "settings.read" },
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
  {
    id: "aiProviders",
    href: "/settings/ai-providers",
    requires: "ai_keys.manage",
  },
];
