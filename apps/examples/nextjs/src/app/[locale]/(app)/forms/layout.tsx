import type { ReactNode } from "react";

import { RouteMessages } from "@/i18n/route-messages";

export default function FormsLayout({ children }: { children: ReactNode }) {
  return (
    <RouteMessages
      namespaces={[
        "announcements",
        "app",
        "dashboard",
        "errors",
        "forms",
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
