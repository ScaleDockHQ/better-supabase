import type { ReactNode } from "react";

import { RouteMessages } from "@/i18n/route-messages";

export default function CareAlertsLayout({
  children,
}: {
  children: ReactNode;
}) {
  return (
    <RouteMessages
      namespaces={[
        "announcements",
        "app",
        "care-alerts",
        "dashboard",
        "errors",
        "inbox",
        "navigation",
        "notifications",
        "offline",
        "organization",
        "search",
        "settings",
        "user",
      ]}
    >
      {children}
    </RouteMessages>
  );
}
