import type { ReactNode } from "react";

import { RouteMessages } from "@/i18n/route-messages";

export default function ComplianceLayout({
  children,
}: {
  children: ReactNode;
}) {
  return (
    <RouteMessages
      namespaces={[
        "acknowledgements",
        "announcements",
        "app",
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
