import type { ReactNode } from "react";

import { RouteMessages } from "@/i18n/route-messages";

export default function CustomersLayout({ children }: { children: ReactNode }) {
  return (
    <RouteMessages
      namespaces={[
        "announcements",
        "app",
        "customers",
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
