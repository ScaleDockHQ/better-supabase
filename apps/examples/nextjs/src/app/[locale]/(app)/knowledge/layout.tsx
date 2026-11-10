import type { ReactNode } from "react";

import { RouteMessages } from "@/i18n/route-messages";

export default function KnowledgeLayout({ children }: { children: ReactNode }) {
  return (
    <RouteMessages
      namespaces={[
        "announcements",
        "app",
        "dashboard",
        "errors",
        "inbox",
        "knowledge",
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
