"use client";

import { useExtracted } from "next-intl";

import { Link, usePathname } from "@/i18n/navigation";
import { cn } from "@/lib/utils";

import { type SettingsTabId, settingsTabs } from "../settings-tabs";

function useTabLabel() {
  const t = useExtracted("settings");
  return (id: SettingsTabId): string => {
    switch (id) {
      case "profile":
        return t("Profile");
      case "security":
        return t("Security");
      case "organization":
        return t("Organization");
      case "members":
        return t("Members");
      case "billing":
        return t("Billing");
      case "apiKeys":
        return t("API keys");
      case "audit":
        return t("Audit log");
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
      className="bg-muted text-muted-foreground inline-flex h-9 w-fit max-w-full items-center overflow-x-auto rounded-lg p-1"
    >
      {settingsTabs
        .filter((tab) => visible.includes(tab.id))
        .map((tab) => {
          const active = pathname === tab.href;
          return (
            <Link
              key={tab.id}
              href={tab.href}
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
