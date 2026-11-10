import type { ReactNode } from "react";

import { RouteMessages } from "@/i18n/route-messages";

export default function CrmLayout({ children }: { children: ReactNode }) {
  return (
    <RouteMessages
      namespaces={[
        "announcements",
        "app",
        "crm",
        "dashboard",
        "errors",
        "inbox",
        "navigation",
        "notifications",
        "offline",
        "organization",
        "search",
        "sequences",
        "settings",
        "user",
      ]}
    >
      {children}
    </RouteMessages>
  );
}
