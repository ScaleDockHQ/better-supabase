import type { ReactNode } from "react";

import { RouteMessages } from "@/i18n/route-messages";

export default function InviteLayout({ children }: { children: ReactNode }) {
  return (
    <RouteMessages
      namespaces={["errors", "invitation", "offline", "organization"]}
    >
      {children}
    </RouteMessages>
  );
}
