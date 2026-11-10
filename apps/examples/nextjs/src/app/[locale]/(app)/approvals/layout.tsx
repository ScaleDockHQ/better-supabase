import type { ReactNode } from "react";

import { RouteMessages } from "@/i18n/route-messages";

export default function ApprovalsLayout({ children }: { children: ReactNode }) {
  return (
    <RouteMessages
      namespaces={[
        "announcements",
        "app",
        "approvals",
        "dashboard",
        "errors",
        "inbox",
        "navigation",
        "notifications",
        "offline",
        "organization",
        "search",
        "settings",
        "subjects",
        "user",
      ]}
    >
      {children}
    </RouteMessages>
  );
}
