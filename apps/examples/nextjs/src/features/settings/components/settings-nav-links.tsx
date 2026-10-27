"use client";

import { useExtracted } from "next-intl";

import { Link, usePathname } from "@/i18n/navigation";
import { cn } from "@/lib/utils";

import type { SettingsTabId } from "../settings-tabs";

import { settingsTabs } from "../settings-tabs";

export function useTabLabel(): (id: SettingsTabId) => string {
  const t = useExtracted("settings");

  return (id: SettingsTabId): string => {
    switch (id) {
      case "profile": {
        return t("Profile");
      }

      case "preferences": {
        return t("Preferences");
      }

      case "integrations": {
        return t("Integrations");
      }

      case "security": {
        return t("Security");
      }

      case "privacy": {
        return t("Privacy");
      }

      case "organization": {
        return t("Organization");
      }

      case "members": {
        return t("Members");
      }

      case "teams": {
        return t("Teams");
      }

      case "roles": {
        return t("Roles");
      }

      case "accessRequests": {
        return t("Access requests");
      }

      case "billing": {
        return t("Billing");
      }

      case "apiKeys": {
        return t("API keys");
      }

      case "webhooks": {
        return t("Webhooks");
      }

      case "signingKeys": {
        return t("Signing keys");
      }

      case "sso": {
        return t("Single sign-on");
      }

      case "customFields": {
        return t("Custom fields");
      }

      case "jobs": {
        return t("Jobs");
      }

      case "audit": {
        return t("Audit log");
      }

      case "aiProviders": {
        return t("AI providers");
      }

      default: {
        const unknown: never = id;

        return unknown;
      }
    }
  };
}

/** Links styled as tabs: each tab is its own route, so each stays instant. */
export function SettingsNavLinks({
  visible,
}: {
  visible: readonly SettingsTabId[];
}) {
  const t = useExtracted("settings");
  const label = useTabLabel();
  const pathname = usePathname();

  return (
    <nav
      aria-label={t("Settings")}
      className="inline-flex h-9 w-fit max-w-full items-center overflow-x-auto rounded-lg bg-muted p-1 text-muted-foreground"
    >
      {settingsTabs
        .filter((tab) => visible.includes(tab.id))
        .map((tab) => {
          const active =
            pathname === tab.href || pathname.startsWith(`${tab.href}/`);

          return (
            <Link
              key={tab.id}
              href={tab.href}
              prefetch
              aria-current={active ? "page" : undefined}
              className={cn(
                "inline-flex h-full items-center rounded-md px-3 text-sm font-medium whitespace-nowrap transition-colors",
                active
                  ? "bg-background text-foreground shadow-sm"
                  : "hover:text-foreground",
              )}
            >
              {label(tab.id)}
            </Link>
          );
        })}
    </nav>
  );
}
