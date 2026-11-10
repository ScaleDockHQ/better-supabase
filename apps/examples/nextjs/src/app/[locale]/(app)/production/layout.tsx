import type { ReactNode } from "react";

import { RouteMessages } from "@/i18n/route-messages";

export default function ProductionLayout({
  children,
}: {
  children: ReactNode;
}) {
  return (
    <RouteMessages
      namespaces={[
        "announcements",
        "app",
        "dashboard",
        "errors",
        "inbox",
        "navigation",
        "notifications",
        "offline",
        "organization",
        "production",
        "search",
        "settings",
        "user",
      ]}
    >
      {children}
    </RouteMessages>
  );
}
