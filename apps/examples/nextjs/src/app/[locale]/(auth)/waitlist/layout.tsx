import type { ReactNode } from "react";

import { RouteMessages } from "@/i18n/route-messages";

export default function WaitlistLayout({ children }: { children: ReactNode }) {
  return (
    <RouteMessages namespaces={["errors", "offline", "waitlist"]}>
      {children}
    </RouteMessages>
  );
}
