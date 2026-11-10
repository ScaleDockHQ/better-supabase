import type { ReactNode } from "react";

import { RouteMessages } from "@/i18n/route-messages";

export default function DriveLayout({ children }: { children: ReactNode }) {
  return (
    <RouteMessages
      namespaces={[
        "announcements",
        "app",
        "dashboard",
        "drive",
        "errors",
        "inbox",
        "navigation",
        "notifications",
        "offline",
        "organization",
        "search",
        "settings",
        "trash",
        "user",
      ]}
    >
      {children}
    </RouteMessages>
  );
}
