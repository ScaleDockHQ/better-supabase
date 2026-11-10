import type { ReactNode } from "react";

import { RouteMessages } from "@/i18n/route-messages";

export default function WorkflowsLayout({ children }: { children: ReactNode }) {
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
        "search",
        "settings",
        "user",
        "workflows",
      ]}
    >
      {children}
    </RouteMessages>
  );
}
