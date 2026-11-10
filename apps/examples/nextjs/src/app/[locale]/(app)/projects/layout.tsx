import type { ReactNode } from "react";

import { RouteMessages } from "@/i18n/route-messages";

export default function ProjectsLayout({ children }: { children: ReactNode }) {
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
        "projects",
        "search",
        "settings",
        "user",
      ]}
    >
      {children}
    </RouteMessages>
  );
}
